local UIManager = require("ui/uimanager")
local logger = require("logger")

-- Must match RubyToggleObscureStyle in lvtextfm.cpp
local OBSCURE = {
    hidden = 0,
    bar = 1,
    blur = 2,
    dissolve = 3,
    bayer2 = 4,
    bayer4 = 5,
    bayer8 = 6,
    checker = 7,
    hatch = 8,
    noise = 9,
}

-- Must match RubyToggleBlurDither in lvtextfm.cpp
local BLUR_DITHER = {
    none = 0,
    dissolve = 1,
    bayer2 = 2,
    bayer4 = 3,
    bayer8 = 4,
    checker = 5,
    hatch = 6,
    noise = 7,
}

local DITHER_STYLES = {
    dissolve = true,
    bayer2 = true,
    bayer4 = true,
    bayer8 = true,
    checker = true,
    hatch = true,
    noise = true,
}

local RubyBackend = {}
RubyBackend.__index = RubyBackend
RubyBackend.OBSCURE = OBSCURE
RubyBackend.BLUR_DITHER = BLUR_DITHER
RubyBackend.DITHER_STYLES = DITHER_STYLES

function RubyBackend:new(ui)
    local o = {
        ui = ui,
        revealed = {},
        toggle_mode = false,
        obscure_style = "hidden",
        blur_radius = 2,
        blur_passes = 2,
        dither_intensity = 70,
        blur_dither = "bayer4",
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

function RubyBackend:_hasObscureApi()
    local doc = self.ui and self.ui.document and self.ui.document._document
    return doc and type(doc.setRubyToggleObscureStyle) == "function"
end

function RubyBackend:_hasBlurApi()
    local doc = self.ui and self.ui.document and self.ui.document._document
    return doc and type(doc.setRubyToggleBlurParams) == "function"
end

function RubyBackend:_hasDitherApi()
    local doc = self.ui and self.ui.document and self.ui.document._document
    return doc and type(doc.setRubyToggleDitherParams) == "function"
end

function RubyBackend:_hasBlurDitherApi()
    local doc = self.ui and self.ui.document and self.ui.document._document
    return doc and type(doc.setRubyToggleBlurDither) == "function"
end

function RubyBackend:isDitherStyle(style)
    return DITHER_STYLES[style or self.obscure_style] == true
end

function RubyBackend:usesIntensity()
    if self:isDitherStyle() then
        return true
    end
    return self.obscure_style == "blur" and self.blur_dither ~= "none"
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
    self:_applyObscureStyle()
    self:_applyBlurParams()
    self:_applyDitherParams()
    self:_applyBlurDither()
    self:_redraw()

    return true
end

function RubyBackend:setObscureStyle(style)
    if not OBSCURE[style] then
        return false
    end
    if self.obscure_style == style then
        self:_applyObscureStyle()
        return true
    end
    self.obscure_style = style
    self:_applyObscureStyle()
    if self.toggle_mode then
        self:_redraw()
    end
    return true
end

function RubyBackend:setBlurParams(radius, passes)
    radius = tonumber(radius) or self.blur_radius
    passes = tonumber(passes) or self.blur_passes
    -- Match CRE safety clamps, UI may offer the same envelope.
    if radius < 0 then radius = 0 end
    if radius > 64 then radius = 64 end
    if passes < 1 then passes = 1 end
    if passes > 20 then passes = 20 end

    local changed = (self.blur_radius ~= radius) or (self.blur_passes ~= passes)
    self.blur_radius = radius
    self.blur_passes = passes
    self:_applyBlurParams()
    if changed and self.toggle_mode and self.obscure_style == "blur" then
        self:_redraw()
    end
    return true
end

function RubyBackend:setDitherParams(intensity)
    intensity = tonumber(intensity) or self.dither_intensity
    if intensity < 0 then intensity = 0 end
    if intensity > 100 then intensity = 100 end

    local changed = self.dither_intensity ~= intensity
    self.dither_intensity = intensity
    self:_applyDitherParams()
    if changed and self.toggle_mode and self:usesIntensity() then
        self:_redraw()
    end
    return true
end

function RubyBackend:setBlurDither(mode)
    if not BLUR_DITHER[mode] then
        return false
    end
    if self.blur_dither == mode then
        self:_applyBlurDither()
        return true
    end
    self.blur_dither = mode
    self:_applyBlurDither()
    if self.toggle_mode and self.obscure_style == "blur" then
        self:_redraw()
    end
    return true
end

function RubyBackend:_applyObscureStyle()
    if not self:_hasObscureApi() then
        return
    end
    self.ui.document._document:setRubyToggleObscureStyle(OBSCURE[self.obscure_style] or 0)
end

function RubyBackend:_applyBlurParams()
    if not self:_hasBlurApi() then
        return
    end
    self.ui.document._document:setRubyToggleBlurParams(self.blur_radius, self.blur_passes)
end

function RubyBackend:_applyDitherParams()
    if not self:_hasDitherApi() then
        return
    end
    self.ui.document._document:setRubyToggleDitherParams(self.dither_intensity)
end

function RubyBackend:_applyBlurDither()
    if not self:_hasBlurDitherApi() then
        return
    end
    self.ui.document._document:setRubyToggleBlurDither(BLUR_DITHER[self.blur_dither] or 0)
end

-------------------------------------------------------------------------------
-- Reveal state
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

function RubyBackend:clearPageState()
    self:clearRevealedState()
end

function RubyBackend:onPageChanged(_page_token)
end

-------------------------------------------------------------------------------
-- Hit testing
-------------------------------------------------------------------------------

function RubyBackend:_rubyIdsFromHit(ruby)
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
