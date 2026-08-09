local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")

local RubyBackend = {}
RubyBackend.__index = RubyBackend


function RubyBackend:_debugMessage(text)
    UIManager:show(InfoMessage:new{
        text = "Furigana debug: " .. tostring(text),
        timeout = 2,
    })
end

function RubyBackend:new(ui)
    local o = {
        ui = ui,
        revealed = {},
        page_token = nil,
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

    return doc.getRubyFromPosition ~= nil
        and doc.setRubyToggleMode ~= nil
        and doc.setRubyVisibilityOverride ~= nil
        and doc.clearRubyVisibilityOverrides ~= nil
end

-------------------------------------------------------------------------------
-- Toggle mode
-------------------------------------------------------------------------------

function RubyBackend:setToggleMode(enabled)
    self.toggle_mode = enabled and true or false
    self.revealed = {}

    self:_debugMessage(
        self.toggle_mode and "Toggle enabled" or "Toggle disabled"
    )

    if not self:isSupported() then
        logger.warn(
            "FuriganaTool: CREngine ruby toggle API unavailable"
        )
        self:_debugMessage("CREngine API unavailable")
        return false
    end

    logger.info(
        "FuriganaTool: setToggleMode",
        self.toggle_mode
    )

    self.ui.document._document:setRubyToggleMode(
        self.toggle_mode
    )

    self.ui.document._document:clearRubyVisibilityOverrides()

    self:_redraw()

    return true
end

-------------------------------------------------------------------------------
-- Page state
-------------------------------------------------------------------------------

function RubyBackend:clearPageState()
    self.revealed = {}

    if self:isSupported() then
        self.ui.document._document:clearRubyVisibilityOverrides()
    end

    if self.toggle_mode then
        self:_redraw()
    end
end

function RubyBackend:onPageChanged(page_token)
    if self.page_token ~= page_token then
        self.page_token = page_token
        self:clearPageState()
    end
end

-------------------------------------------------------------------------------
-- Hit testing
-------------------------------------------------------------------------------

function RubyBackend:getRubyAtScreenPosition(screen_pos)
    if not self:isSupported() then
        logger.warn("FuriganaTool: backend unsupported")
        return nil
    end

    if not screen_pos then
        return nil
    end

    local x = math.floor(screen_pos.x)
    local y = math.floor(screen_pos.y)

    logger.info(
        "FuriganaTool: tap",
        x,
        y
    )

    self:_debugMessage(
        "Tap " .. tostring(x) .. "," .. tostring(y)
    )

    local ruby = self.ui.document._document:getRubyFromPosition(
        x,
        y
    )

    if ruby and ruby.id then
        logger.info(
            "FuriganaTool: ruby hit",
            ruby.id
        )

        self:_debugMessage(
            "Ruby found: " .. tostring(ruby.id)
        )

        return ruby
    end

    logger.info("FuriganaTool: no ruby at tap")
    self:_debugMessage("No ruby found")

    return nil
end

-------------------------------------------------------------------------------
-- Visibility
-------------------------------------------------------------------------------

function RubyBackend:setRubyVisible(ruby_id, visible)
    if not self:isSupported() then
        return false
    end

    if not ruby_id then
        return false
    end

    local ok =
        self.ui.document._document:setRubyVisibilityOverride(
            ruby_id,
            visible and true or false
        )

    if not ok then
        logger.warn(
            "FuriganaTool: visibility override failed",
            ruby_id
        )

        return false
    end

    logger.info(
        "FuriganaTool: ruby visibility",
        ruby_id,
        visible
    )

    self:_debugMessage(
        visible and "Visibility ON" or "Visibility OFF"
    )

    self:_redraw()

    return true
end

-------------------------------------------------------------------------------
-- Actual tap toggle
-------------------------------------------------------------------------------

function RubyBackend:toggleAtScreenPosition(screen_pos)
    if not self.toggle_mode then
        return false
    end

    local ruby = self:getRubyAtScreenPosition(screen_pos)

    if not ruby or not ruby.id then
        return false
    end

    local id = ruby.id
    local new_visible = not self.revealed[id]

    if not self:setRubyVisible(id, new_visible) then
        return false
    end

    if new_visible then
        self.revealed[id] = true
    else
        self.revealed[id] = nil
    end

    return true
end

-------------------------------------------------------------------------------
-- Redraw without reflow
-------------------------------------------------------------------------------

function RubyBackend:_redraw()
    if not self.ui then
        return
    end

    if self.ui.view then
        UIManager:setDirty(
            self.ui.view,
            "ui"
        )
    else
        UIManager:setDirty(
            nil,
            "ui"
        )
    end
end

return RubyBackend
