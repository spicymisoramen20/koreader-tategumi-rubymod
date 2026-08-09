local UIManager = require("ui/uimanager")
local logger = require("logger")

local RubyBackend = {}
RubyBackend.__index = RubyBackend

function RubyBackend:new(ui)
    local o = {
        ui = ui,
        revealed = {},
        toggle_mode = false,
    }

    return setmetatable(o, self)
end

-------------------------------------------------------------------------------
-- Engine availability
-------------------------------------------------------------------------------

function RubyBackend:isSupported()
    local doc = self.ui
        and self.ui.document
        and self.ui.document._document

    if not doc then
        return false
    end

    return type(doc.getRubyFromPosition) == "function"
        and type(doc.setRubyToggleMode) == "function"
        and type(doc.setRubyVisibilityOverride) == "function"
        and type(doc.clearRubyVisibilityOverrides) == "function"
end

-------------------------------------------------------------------------------
-- Toggle mode
-------------------------------------------------------------------------------

function RubyBackend:setToggleMode(enabled)
    self.toggle_mode = enabled and true or false
    self.revealed = {}

    if not self:isSupported() then
        logger.warn("FuriganaTool: api_supported=false")
        return false
    end

    logger.dbg("FuriganaTool: toggle=", self.toggle_mode)

    self.ui.document._document:setRubyToggleMode(self.toggle_mode)
    self.ui.document._document:clearRubyVisibilityOverrides()
    self:_redraw()

    return true
end

-------------------------------------------------------------------------------
-- Reveal state
--
-- Reveals persist for the whole document session while Toggle is active.
-- They are cleared only on mode change / document close — not on page turns
-- or paint refreshes (those were wiping reveals and looking like a loading
-- re-render).
-------------------------------------------------------------------------------

function RubyBackend:clearRevealedState()
    self.revealed = {}

    if self:isSupported() then
        self.ui.document._document:clearRubyVisibilityOverrides()
    end

    if self.toggle_mode then
        self:_redraw()
    end
end

-- Kept for call sites that previously meant "page-local" clears.
function RubyBackend:clearPageState()
    self:clearRevealedState()
end

function RubyBackend:onPageChanged(_page_token)
    -- Intentionally no-op: revealed furigana stay until retapped or mode exits.
end

-------------------------------------------------------------------------------
-- Hit testing
-------------------------------------------------------------------------------

function RubyBackend:_rubyIdsFromHit(ruby)
    if not ruby then
        return {}
    end

    -- Preferred: contiguous sibling ruby group from native hit-test.
    if type(ruby.ids) == "table" and #ruby.ids > 0 then
        return ruby.ids
    end

    if ruby.id then
        return { ruby.id }
    end

    return {}
end

function RubyBackend:getRubyAtScreenPosition(screen_pos)
    if not self:isSupported() or not screen_pos then
        return nil
    end

    local x = math.floor(screen_pos.x)
    local y = math.floor(screen_pos.y)
    local ruby = self.ui.document._document:getRubyFromPosition(x, y)
    local ids = self:_rubyIdsFromHit(ruby)
    if #ids == 0 then
        return nil
    end

    return {
        id = ids[1],
        ids = ids,
    }
end

-------------------------------------------------------------------------------
-- Visibility
-------------------------------------------------------------------------------

function RubyBackend:setRubyVisible(ruby_id, visible)
    if not self:isSupported() or not ruby_id then
        return false
    end

    local ok = self.ui.document._document:setRubyVisibilityOverride(
        ruby_id,
        visible and true or false
    )
    if not ok then
        logger.warn("FuriganaTool: visibility override failed", ruby_id)
        return false
    end

    return true
end

function RubyBackend:setRubyGroupVisible(ruby_ids, visible)
    if not ruby_ids or #ruby_ids == 0 then
        return false
    end

    local any = false
    for _, id in ipairs(ruby_ids) do
        if self:setRubyVisible(id, visible) then
            any = true
            if visible then
                self.revealed[id] = true
            else
                self.revealed[id] = nil
            end
        end
    end

    if any then
        self:_redraw()
    end
    return any
end

-------------------------------------------------------------------------------
-- Actual tap toggle
-------------------------------------------------------------------------------

function RubyBackend:toggleAtScreenPosition(screen_pos)
    if not self.toggle_mode or not self:isSupported() then
        return false
    end

    local ruby = self:getRubyAtScreenPosition(screen_pos)
    if not ruby or not ruby.ids then
        return false
    end

    local ids = ruby.ids
    -- If any member of the group is hidden, reveal the whole group.
    -- If all are revealed, hide the whole group.
    local any_hidden = false
    for _, id in ipairs(ids) do
        if not self.revealed[id] then
            any_hidden = true
            break
        end
    end

    return self:setRubyGroupVisible(ids, any_hidden)
end

-------------------------------------------------------------------------------
-- Redraw without reflow
-------------------------------------------------------------------------------

function RubyBackend:_redraw()
    if not self.ui then
        return
    end

    -- Paint-time ruby visibility does not change CRE layout/pos tags.
    -- Trash only the page blitbuffer so drawCurrentView re-paints from CRE
    -- without a full stylesheet / reflow (no loading bar).
    local doc = self.ui.document
    if doc then
        if type(doc.resetBufferCache) == "function" then
            doc:resetBufferCache()
        elseif type(doc._callCacheSet) == "function" then
            doc._callCacheSet("current_buffer_tag", nil)
        end
    end

    local widget = nil
    if self.ui.view then
        widget = self.ui.view.dialog or self.ui.view
    end
    UIManager:setDirty(widget, "ui")
end

return RubyBackend
