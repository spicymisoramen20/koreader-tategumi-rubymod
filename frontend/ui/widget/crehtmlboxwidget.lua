--[[--
HTML snippet widget rendered with CREngine (no scroll bars).

Used for footnote popups that need CSS Ruby / furigana Off/Toggle paint.
Creates a temporary XHTML file and a short-lived DocView; destroys both on free.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local HighlightGeom = require("ui/highlightgeom")
local Screen = Device.screen

-- Furigana Off CSS (keep in sync with plugins/furiganatool.koplugin/styles.lua).
local FURIGANA_OFF_CSS = [[
rt { display: none !important; }
rp { display: none !important; }
]]

local FURIGANA_TOGGLE_CSS = [[
rp { display: none !important; }
]]

local OBSCURE = {
    hidden = 0,
    bar = 1,
    fog = 2,
}

local CreHtmlBoxWidget = InputContainer:extend{
    bb = nil,
    dimen = nil,
    dialog = nil,
    document = nil, -- cre userdata
    page_count = 0,
    page_number = 1,
    html_link_tapped_callback = nil,
    -- Furigana (optional; FootnoteWidget passes book settings)
    furigana_toggle_mode = "visible", -- visible | off | toggle
    furigana_toggle_obscure = "hidden",
    furigana_toggle_dither_intensity = 10,
    furigana_toggle_fog_falloff = 5,
    furigana_toggle_fog_roundness = 15,
    ruby_tap_callback = nil, -- function(handled) optional; if nil, handle taps locally
    -- Hold selection / dictionary (parity with HtmlBoxWidget)
    highlight_text_selection = true,
    hold_start_pos = nil,
    hold_end_pos = nil,
    hold_start_time = nil,
    highlight_text = nil,
    highlight_rects = nil,
    highlight_clear_and_redraw_action = nil,
    -- True after HoldStart until HoldPan: expand CJK via japanese.koplugin.
    is_word_selection = false,
    -- Internal
    _tmp_path = nil,
    _revealed = nil, -- map of ruby xpointer id -> true (popup-local only)
}

function CreHtmlBoxWidget:init()
    self._revealed = {}
    self.highlight_lighten_factor = G_reader_settings:readSetting("highlight_lighten_factor", 0.2)
    if Device:isTouchDevice() then
        self.ges_events.TapText = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        }
    end
end

local function wrapXhtml(body)
    return table.concat({
        '<?xml version="1.0" encoding="UTF-8"?>\n',
        '<html xmlns="http://www.w3.org/1999/xhtml">\n',
        "<head><title>footnote</title></head>\n",
        "<body>\n",
        body or "",
        "\n</body>\n</html>\n",
    })
end

-- getHTMLFromXPointer serializes CRE's internal ruby/float boxing tree
-- (inlineBox / rubyBox / autoBoxing / …). Reloading that tree into a fresh
-- horizontal DocView skips re-boxing and can leave <rt> flowing beside the
-- base instead of over it. Unwrap to plain ruby markup so CRE re-boxes for
-- horizontal-tb.
local BOXING_TAGS = {
    "inlineBox", "rubyBox", "autoBoxing", "floatBox", "tabularBox", "mathBox",
}
local function stripCreBoxingMarkup(html)
    if not html or html == "" then
        return html
    end
    for _, tag in ipairs(BOXING_TAGS) do
        -- Opening tags with optional attributes, and matching closers.
        html = html:gsub("</?" .. tag .. "%f[%s>/][^>]*>", "")
    end
    return html
end

function CreHtmlBoxWidget:_writeTempFile(xhtml)
    local dir = DataStorage:getDataDir() .. "/cache"
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(dir)
    end
    local path = string.format("%s/footnote_cre_%s_%s.xhtml",
        dir, tostring(os.time()), tostring(math.random(100000, 999999)))
    local f, err = io.open(path, "wb")
    if not f then
        return nil, err
    end
    f:write(xhtml)
    f:close()
    return path
end

function CreHtmlBoxWidget:_buildAppendedCss(extra_css)
    local parts = {
        [[
/* Force horizontal layout for the whole snippet (book may be vertical-rl). */
html, body, body * {
  writing-mode: horizontal-tb !important;
}
html, body {
  margin: 0;
  padding: 0;
  line-height: 1.3;
}
h1, h2, h3, h4, h5, h6, p, blockquote, pre, ol, ul, dl { margin: 0; }
blockquote, dd { margin-left: 1em; margin-right: 1em; }
body > li { list-style-type: none; }
.noprint { display: none; }
a { color: black; }
/* Explicit ruby rules so annotations sit above the base in horizontal-tb,
 * even if epub.css / html5.css fail to load for this temp DocView. */
ruby {
  display: ruby !important;
  ruby-position: over !important;
  text-align: center;
  text-indent: 0;
}
rb, rubyBox[T=rb] {
  line-height: 1;
}
rt, rubyBox[T=rt] {
  line-height: 1.6;
  font-size: 42%;
  font-variant-east-asian: ruby;
}
]],
    }
    if self.furigana_toggle_mode == "off" then
        table.insert(parts, FURIGANA_OFF_CSS)
    elseif self.furigana_toggle_mode == "toggle" then
        table.insert(parts, FURIGANA_TOGGLE_CSS)
    end
    if extra_css and extra_css ~= "" then
        table.insert(parts, extra_css)
    end
    return table.concat(parts, "\n")
end

function CreHtmlBoxWidget:_applyTogglePaintState()
    if not self.document or self.furigana_toggle_mode ~= "toggle" then
        return
    end
    -- Process-global flags; book Toggle already sets these. Re-assert for the popup.
    if type(self.document.setRubyToggleMode) == "function" then
        self.document:setRubyToggleMode(true)
    end
    if type(self.document.setRubyToggleObscureStyle) == "function" then
        self.document:setRubyToggleObscureStyle(OBSCURE[self.furigana_toggle_obscure] or 0)
    end
    if type(self.document.setRubyToggleDitherParams) == "function" then
        self.document:setRubyToggleDitherParams(self.furigana_toggle_dither_intensity or 10)
    end
    if type(self.document.setRubyToggleFogParams) == "function" then
        self.document:setRubyToggleFogParams(
            self.furigana_toggle_fog_falloff or 5,
            self.furigana_toggle_fog_roundness or 15)
    end
end

function CreHtmlBoxWidget:_clearPopupReveals()
    if not self.document or not self._revealed then
        return
    end
    if type(self.document.setRubyVisibilityOverride) ~= "function" then
        return
    end
    -- Do not call clearRubyVisibilityOverrides(): that would wipe the book's reveals.
    for id, _ in pairs(self._revealed) do
        pcall(function()
            self.document:setRubyVisibilityOverride(id, false)
        end)
    end
    self._revealed = {}
end

--- Load and layout an HTML/XHTML body snippet.
-- @string body HTML fragment (typically from getHTMLFromXPointer)
-- @string css Extra CSS appended after base + furigana rules
-- @number default_font_size Font size in screen pixels
-- @string font_face Optional CRE font face name
function CreHtmlBoxWidget:setContent(body, css, default_font_size, font_face)
    self:freeDocument()

    local xhtml = wrapXhtml(stripCreBoxingMarkup(body))
    local path, err = self:_writeTempFile(xhtml)
    if not path then
        logger.err("CreHtmlBoxWidget: temp file failed:", err)
        self.page_count = 0
        return
    end
    self._tmp_path = path

    local CreDocument = require("document/credocument")
    local cre = CreDocument:engineInit()
    local PAGE_VIEW_MODE = CreDocument.PAGE_VIEW_MODE

    local ok, document = pcall(cre.newDocView, self.dimen.w, self.dimen.h, PAGE_VIEW_MODE)
    if not ok then
        logger.err("CreHtmlBoxWidget: newDocView failed:", document)
        self:_removeTempFile()
        return
    end
    self.document = document

    -- Avoid disk cache for tiny temp snippets (and never call readDefaults:
    -- that mutates process-global CRE state used by the open book).
    self.document:setIntProperty("crengine.cache.filesize.min", 2147483647)
    self.document:setIntProperty("crengine.doc.embedded.styles.enabled", 1)
    self.document:setIntProperty("crengine.doc.embedded.fonts.enabled", 0)
    self.document:setHeaderInfo(0)
    self.document:setPageMargins(0, 0, 0, 0)

    -- Each DocView has its own props; without readDefaults we still need CJK fallbacks.
    local fallbacks = {}
    local user_fallback = G_reader_settings:readSetting("fallback_font")
    if user_fallback then
        table.insert(fallbacks, user_fallback)
    end
    for _, name in ipairs(CreDocument.fallback_fonts) do
        table.insert(fallbacks, name)
    end
    self.document:setStringProperty("crengine.font.fallback.faces", table.concat(fallbacks, "|"))

    if font_face and font_face ~= "" then
        self.document:setFontFace(font_face)
    end
    if default_font_size and default_font_size > 0 then
        self.document:setFontSize(default_font_size)
    end

    local appended = self:_buildAppendedCss(css)
    -- Prefer epub.css so ruby / common HTML elements match book rendering.
    self.document:setStyleSheet("./data/epub.css", appended)

    local loaded = self.document:loadDocument(path)
    if not loaded then
        logger.err("CreHtmlBoxWidget: loadDocument failed:", path)
        self:freeDocument()
        return
    end

    self.document:renderDocument()
    self.page_count = self.document:getPages() or 1
    if self.page_count < 1 then
        self.page_count = 1
    end
    self.page_number = 1
    self.document:gotoPage(1)
    self:_applyTogglePaintState()
    self:freeBb()
end

function CreHtmlBoxWidget:_removeTempFile()
    if self._tmp_path then
        os.remove(self._tmp_path)
        self._tmp_path = nil
    end
end

function CreHtmlBoxWidget:freeDocument()
    self:_clearPopupReveals()
    if self.document then
        pcall(function() self.document:closeDocument() end)
        self.document = nil
    end
    self:_removeTempFile()
    self.page_count = 0
    self.page_number = 1
end

function CreHtmlBoxWidget:_render()
    if self.bb or not self.document then
        return
    end
    local w, h = self.dimen.w, self.dimen.h
    local color = Screen:isColorEnabled()
    self.bb = Blitbuffer.new(w, h, color and Blitbuffer.TYPE_BBRGB32 or nil)
    self.bb:fill(Blitbuffer.COLOR_WHITE)
    -- drawCurrentPage resizes/renders to the buffer size and draws page content.
    self.document:drawCurrentPage(
        self.bb,
        color,
        Screen.night_mode and true or false,
        false,
        Screen.sw_dithering and true or false
    )
    if self.highlight_text_selection and self.highlight_rects then
        -- Footnote-only pad (unpaired from book CROSS_PAD_PX).
        local pad = HighlightGeom.FOOTNOTE_CROSS_PAD_PX
        for _, rect in ipairs(self.highlight_rects) do
            local x, y, w, h = HighlightGeom.padCrossAxis(
                rect.x, rect.y, rect.w, rect.h, false, pad)
            self.bb:darkenRect(x, y, w, h, self.highlight_lighten_factor)
        end
    end
end

function CreHtmlBoxWidget:getSize()
    return self.dimen
end

function CreHtmlBoxWidget:getSinglePageHeight()
    if not self.document or self.page_count ~= 1 then
        return
    end
    local fh = self.document:getFullHeight()
    if fh and fh > 0 and fh < self.dimen.h then
        return math.ceil(fh)
    end
end

function CreHtmlBoxWidget:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    self:_render()
    if self.bb then
        local size = self:getSize()
        bb:blitFrom(self.bb, x, y, 0, 0, size.w, size.h)
    end
end

function CreHtmlBoxWidget:freeBb()
    if self.bb and self.bb.free then
        self.bb:free()
    end
    self.bb = nil
end

function CreHtmlBoxWidget:free()
    self:freeBb()
    self:freeDocument()
end

function CreHtmlBoxWidget:onCloseWidget()
    self:free()
end

function CreHtmlBoxWidget:setPageNumber(page_number)
    if not self.document then
        return
    end
    if page_number < 1 then
        page_number = 1
    elseif page_number > self.page_count then
        page_number = self.page_count
    end
    if page_number ~= self.page_number then
        self.page_number = page_number
        self.document:gotoPage(page_number)
        self:clearHighlight()
        self:freeBb()
    end
end

function CreHtmlBoxWidget:getPosFromAbsPos(abs_pos)
    local pos = Geom:new{
        x = abs_pos.x - self.dimen.x,
        y = abs_pos.y - self.dimen.y,
    }
    if pos.x < 0 or pos.x >= self.dimen.w or pos.y < 0 or pos.y >= self.dimen.h then
        return nil
    end
    return pos
end

function CreHtmlBoxWidget:_rubyIdsFromHit(ruby)
    if not ruby then
        return {}
    end
    if type(ruby.ids) == "table" and #ruby.ids > 0 then
        return ruby.ids
    end
    if ruby.id then
        return { ruby.id }
    end
    return {}
end

function CreHtmlBoxWidget:_toggleRubyAtPos(pos)
    if self.furigana_toggle_mode ~= "toggle" or not self.document then
        return false
    end
    if type(self.document.getRubyFromPosition) ~= "function" then
        return false
    end
    local ruby = self.document:getRubyFromPosition(math.floor(pos.x), math.floor(pos.y))
    local ids = self:_rubyIdsFromHit(ruby)
    if #ids == 0 then
        return false
    end

    local any_hidden = false
    for _, id in ipairs(ids) do
        if not self._revealed[id] then
            any_hidden = true
            break
        end
    end
    local visible = any_hidden
    local any = false
    for _, id in ipairs(ids) do
        local ok = self.document:setRubyVisibilityOverride(id, visible)
        if ok then
            any = true
            if visible then
                self._revealed[id] = true
            else
                self._revealed[id] = nil
            end
        end
    end
    if any then
        self:freeBb()
        UIManager:setDirty(self.dialog or "all", function()
            return "ui", self.dimen
        end)
    end
    return any
end

function CreHtmlBoxWidget:onTapText(arg, ges)
    local pos = self:getPosFromAbsPos(ges.pos)
    if not pos then
        return
    end

    if self.furigana_toggle_mode == "toggle" then
        if self:_toggleRubyAtPos(pos) then
            return true
        end
    end

    -- Link follow inside footnotes is unused today; keep hook for API parity.
    if self.html_link_tapped_callback and G_reader_settings:nilOrTrue("tap_to_follow_links") then
        -- CRE link hit-testing not implemented for v1.
    end
end

-- Hold selection for dictionary / Wikipedia lookup (parity with HtmlBoxWidget).
-- Native CRE selection paint is not used: drawCurrentPage re-Renders each time,
-- so we paint highlight_rects ourselves after the page blit.
-- Point holds expand via japanese.koplugin (same as ReaderHighlight), because
-- CRE getTextFromPositions at a point returns a single CJK character.

function CreHtmlBoxWidget:clearHighlight()
    self.hold_start_pos = nil
    self.hold_end_pos = nil
    self.is_word_selection = false
    return self:updateHighlight()
end

-- Expand a single-char CJK hold using LanguageSupport / japanese.koplugin.
-- Uses the popup DocView (not the book) for xpointer walks.
function CreHtmlBoxWidget:_snapRangeOffRubyAnnotations(range)
    if not (range and range.pos0 and range.pos1 and self.document) then
        return range
    end
    local doc = self.document
    if type(doc.isRubyAnnotationXPointer) ~= "function"
            or type(doc.getPrevVisibleChar) ~= "function"
            or type(doc.getNextVisibleChar) ~= "function" then
        return range
    end

    local pos0, pos1 = range.pos0, range.pos1
    local changed = false

    -- Hold on furigana: walk back onto the base character.
    for _ = 1, 128 do
        local ok, is_rt = pcall(function() return doc:isRubyAnnotationXPointer(pos0) end)
        if not ok or not is_rt then
            break
        end
        local prev = doc:getPrevVisibleChar(pos0)
        if not prev or prev == pos0 then
            break
        end
        pos0 = prev
        changed = true
    end

    -- Exclusive end on/after <rt>: land just after the last base char.
    for _ = 1, 128 do
        local ok, is_rt = pcall(function() return doc:isRubyAnnotationXPointer(pos1) end)
        if not ok or not is_rt then
            break
        end
        local prev = doc:getPrevVisibleChar(pos1)
        if prev and not doc:isRubyAnnotationXPointer(prev) then
            local nxt = doc:getNextVisibleChar(prev)
            if nxt then
                pos1 = nxt
                changed = true
            end
            break
        end
        local nxt = doc:getNextVisibleChar(pos1)
        if not nxt or nxt == pos1 then
            break
        end
        pos1 = nxt
        changed = true
    end

    if not changed then
        return range
    end

    local text_ok, text = pcall(function()
        return doc:getTextFromXPointers(pos0, pos1)
    end)
    if not text_ok or not text or text == "" then
        return range
    end
    return {
        text = util.cleanupSelectedText(text),
        pos0 = pos0,
        pos1 = pos1,
    }
end

function CreHtmlBoxWidget:_improveWordSelection(range)
    if not range or not range.text or range.text == "" then
        return nil
    end
    if not util.hasCJKChar(range.text) then
        return nil
    end
    if not (range.pos0 and range.pos1 and self.document) then
        return nil
    end

    local ls = self.dialog and self.dialog.languagesupport
    if not ls or not ls:hasActiveLanguagePlugins() then
        return nil
    end

    local language_code = "ja"
    if self.dialog.doc_props and self.dialog.doc_props.language then
        language_code = self.dialog.doc_props.language
    elseif ls.ui and ls.ui.doc_props and ls.ui.doc_props.language then
        language_code = ls.ui.doc_props.language
    end

    local doc = self.document
    local callbacks = {
        get_prev_char_pos = function(pos)
            return doc:getPrevVisibleChar(pos)
        end,
        get_next_char_pos = function(pos)
            return doc:getNextVisibleChar(pos)
        end,
        get_text_in_range = function(pos0, pos1)
            return doc:getTextFromXPointers(pos0, pos1)
        end,
    }

    local new_pos0, new_pos1 = unpack(ls:_findAndCallPlugin(
        language_code, "WordSelection",
        {
            text = range.text,
            pos0 = range.pos0,
            pos1 = range.pos1,
            callbacks = callbacks,
        }
    ) or {})
    if not new_pos0 or not new_pos1 then
        return nil
    end
    if new_pos0 == range.pos0 and new_pos1 == range.pos1 then
        return nil
    end

    local text_ok, new_text = pcall(function()
        return doc:getTextFromXPointers(new_pos0, new_pos1)
    end)
    if not text_ok or not new_text or new_text == "" then
        return nil
    end

    return {
        text = util.cleanupSelectedText(new_text),
        pos0 = new_pos0,
        pos1 = new_pos1,
    }
end

function CreHtmlBoxWidget:updateHighlight()
    if not (self.hold_start_pos and self.hold_end_pos and self.document) then
        local changed = self.highlight_rects ~= nil
        self.highlight_rects = nil
        self.highlight_text = nil
        if self.document and type(self.document.clearSelection) == "function" then
            pcall(function() self.document:clearSelection() end)
        end
        return changed
    end

    -- drawSelection=false: we paint boxes ourselves after drawCurrentPage.
    local ok, range = pcall(function()
        return self.document:getTextFromPositions(
            math.floor(self.hold_start_pos.x), math.floor(self.hold_start_pos.y),
            math.floor(self.hold_end_pos.x), math.floor(self.hold_end_pos.y),
            false, false)
    end)
    if not ok or not range or not range.text or range.text == "" then
        local changed = self.highlight_text ~= nil
        self.highlight_text = nil
        self.highlight_rects = nil
        return changed
    end

    -- Furigana hits: snap onto base before expand / boxes (segments skip <rt>).
    range = self:_snapRangeOffRubyAnnotations(range)

    if self.is_word_selection then
        local improved = self:_improveWordSelection(range)
        if improved then
            range = improved
        end
        range = self:_snapRangeOffRubyAnnotations(range)
    end

    local rects = {}
    if range.pos0 and range.pos1 and type(self.document.getWordBoxesFromPositions) == "function" then
        local boxes_ok, boxes = pcall(function()
            return self.document:getWordBoxesFromPositions(range.pos0, range.pos1, true)
        end)
        if boxes_ok and type(boxes) == "table" then
            for _, b in ipairs(boxes) do
                if b.x0 and b.y0 and b.x1 and b.y1 then
                    table.insert(rects, Geom:new{
                        x = b.x0,
                        y = b.y0,
                        w = math.max(1, b.x1 - b.x0),
                        h = math.max(1, b.y1 - b.y0),
                    })
                end
            end
        end
    end

    -- If boxes are empty (exclusive end still on ruby), try one more snap+fetch.
    if #rects == 0 and range.pos0 and range.pos1 then
        range = self:_snapRangeOffRubyAnnotations(range)
        local boxes_ok, boxes = pcall(function()
            return self.document:getWordBoxesFromPositions(range.pos0, range.pos1, true)
        end)
        if boxes_ok and type(boxes) == "table" then
            for _, b in ipairs(boxes) do
                if b.x0 and b.y0 and b.x1 and b.y1 then
                    table.insert(rects, Geom:new{
                        x = b.x0,
                        y = b.y0,
                        w = math.max(1, b.x1 - b.x0),
                        h = math.max(1, b.y1 - b.y0),
                    })
                end
            end
        end
    end

    local prev_text = self.highlight_text
    local prev_n = self.highlight_rects and #self.highlight_rects or 0
    self.highlight_text = range.text
    self.highlight_rects = #rects > 0 and rects or nil
    return prev_text ~= range.text or prev_n ~= (#rects)
end

function CreHtmlBoxWidget:redrawHighlight()
    if not self.highlight_text_selection then
        return
    end
    self:freeBb()
    UIManager:setDirty(self.dialog or "all", function()
        return "ui", self.dimen
    end)
end

function CreHtmlBoxWidget:scheduleClearHighlightAndRedraw()
    if self.highlight_clear_and_redraw_action then
        return
    end
    self.highlight_clear_and_redraw_action = function()
        self.highlight_clear_and_redraw_action = nil
        if self:clearHighlight() then
            self:redrawHighlight()
        end
    end
    UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), self.highlight_clear_and_redraw_action)
end

function CreHtmlBoxWidget:unscheduleClearHighlightAndRedraw()
    if self.highlight_clear_and_redraw_action then
        UIManager:unschedule(self.highlight_clear_and_redraw_action)
        self.highlight_clear_and_redraw_action = nil
    end
end

function CreHtmlBoxWidget:onHoldStartText(_, ges)
    self:unscheduleClearHighlightAndRedraw()
    self.hold_start_pos = self:getPosFromAbsPos(ges.pos)
    self.hold_end_pos = self.hold_start_pos
    self.highlight_rects = nil
    self.highlight_text = nil
    self.is_word_selection = true

    if not self.hold_start_pos then
        return false
    end

    self.hold_start_time = UIManager:getTime()
    if self:updateHighlight() then
        self:redrawHighlight()
    end
    return true
end

function CreHtmlBoxWidget:onHoldPanText(_, ges)
    if not self.hold_start_pos then
        return false
    end
    self.hold_end_pos = Geom:new{
        x = ges.pos.x - self.dimen.x,
        y = ges.pos.y - self.dimen.y,
    }
    -- Ignore micro-pans (common before hold_release); keep word expansion.
    local dx = self.hold_end_pos.x - self.hold_start_pos.x
    local dy = self.hold_end_pos.y - self.hold_start_pos.y
    local pan_slop = Screen:scaleBySize(8)
    if (dx * dx + dy * dy) > (pan_slop * pan_slop) then
        self.is_word_selection = false
    end
    if self:updateHighlight() then
        self.hold_start_time = UIManager:getTime()
        self:redrawHighlight()
    end
    return true
end

function CreHtmlBoxWidget:onHoldReleaseText(callback, ges)
    if not callback or not self.hold_start_pos then
        return false
    end
    self.hold_end_pos = Geom:new{
        x = ges.pos.x - self.dimen.x,
        y = ges.pos.y - self.dimen.y,
    }
    if self:updateHighlight() then
        self:redrawHighlight()
    end
    if not self.highlight_text or self.highlight_text == "" then
        return false
    end
    local hold_duration = time.now() - self.hold_start_time
    callback(self.highlight_text, hold_duration)
    return true
end

return CreHtmlBoxWidget
