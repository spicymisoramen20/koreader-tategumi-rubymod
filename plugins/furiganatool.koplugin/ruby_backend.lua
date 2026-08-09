-- CREngine bridge for Furigana Tool.
--
-- Toggle mode now uses CREngine paint-time visibility. Ruby layout remains
-- unchanged; only <rt> painting is suppressed/re-enabled.

local UIManager = require("ui/uimanager")

local RubyBackend = {}
RubyBackend.__index = RubyBackend

function RubyBackend:new(ui)
    return setmetatable({
        ui = ui,
        revealed = {},
        page_token = nil,
        toggle_mode = false,
    }, self)
end

function RubyBackend:isSupported()
    return self.ui
        and self.ui.document
        and self.ui.document._document
        and not self.ui.document.info.has_pages
        and self.ui.document._document.getRubyFromPosition
        and self.ui.document._document.setRubyToggleMode
        and self.ui.document._document.setRubyVisibilityOverride
        and self.ui.document._document.clearRubyVisibilityOverrides
end

function RubyBackend:setToggleMode(enabled)
    if not self:isSupported() then
        return false
    end

    self.toggle_mode = enabled and true or false
    self.ui.document._document:setRubyToggleMode(self.toggle_mode)

    if not self.toggle_mode then
        self.revealed = {}
    end

    return true
end

function RubyBackend:clearPageState()
    self.revealed = {}

    if self:isSupported() then
        self.ui.document._document:clearRubyVisibilityOverrides()
    end
end

function RubyBackend:onPageChanged(page_token)
    if self.page_token ~= page_token then
        self.page_token = page_token
        self:clearPageState()
    end
end

function RubyBackend:getRubyAtScreenPosition(screen_pos)
    if not self:isSupported() or not screen_pos then
        return nil
    end

    -- CREngine's hit testing expects window/screen coordinates here,
    -- just like getNearestWordFromPosition().
    return self.ui.document._document:getRubyFromPosition(
        math.floor(screen_pos.x),
        math.floor(screen_pos.y)
    )
end

function RubyBackend:setRubyVisible(ruby_id, visible)
    if not self:isSupported() then
        return false
    end

    local ok = self.ui.document._document:setRubyVisibilityOverride(
        ruby_id,
        visible and true or false
    )

    if not ok then
        return false
    end

    -- No reflow. We only need the current view repainted.
    if self.ui.view then
        UIManager:setDirty(self.ui.view, "ui")
    end

    return true
end

function RubyBackend:toggleAtScreenPosition(screen_pos)
    local ruby = self:getRubyAtScreenPosition(screen_pos)

    if not ruby or not ruby.id then
        return false
    end

    local id = ruby.id
    local visible = not self.revealed[id]

    if not self:setRubyVisible(id, visible) then
        return false
    end

    if visible then
        self.revealed[id] = true
    else
        self.revealed[id] = nil
    end

    return true
end

return RubyBackend
