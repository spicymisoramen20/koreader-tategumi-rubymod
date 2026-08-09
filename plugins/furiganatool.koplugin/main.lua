local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Styles = require("styles")
local RubyBackend = require("ruby_backend")

local FuriganaToggle = WidgetContainer:extend{
    name = "furiganatoggle",
    is_doc_only = true,
}

local SETTING_KEY = "furigana_toggle_mode"
local VALID_MODES = {
    visible = true,
    off = true,
    toggle = true,
}

function FuriganaToggle:init()
    self.mode = self.ui.doc_settings:readSetting(SETTING_KEY) or "visible"
    if not VALID_MODES[self.mode] then
        self.mode = "visible"
    end

    self.backend = RubyBackend:new(self.ui)
    self._plugin_css = ""
    self:_installCssInjection()

    self.ui.menu:registerToMainMenu(self)
end

function FuriganaToggle:_installCssInjection()
    local styletweak = self.ui.styletweak
    if not styletweak or self._css_hook_installed then
        return
    end

    self._original_getCssText = styletweak.getCssText
    local plugin = self

    styletweak.getCssText = function(st)
        local base = plugin._original_getCssText(st)
        local extra = plugin._plugin_css

        if not extra or extra == "" then
            return base
        end
        if not base or base == "" then
            return extra
        end
        return base .. "\n" .. extra
    end

    self._css_hook_installed = true
end

function FuriganaToggle:_applyCss()
    if not self.backend:isSupported() then
        self._plugin_css = ""
        return
    end

    self._plugin_css = Styles[self.mode] or ""

    -- Toggle uses paint-time CREngine suppression; visible/off do not.
    self.backend:setToggleMode(self.mode == "toggle")

    self.ui:handleEvent(Event:new("ApplyStyleSheet"))
end

function FuriganaToggle:setMode(mode)
    if not VALID_MODES[mode] or mode == self.mode then
        return
    end

    self.mode = mode
    self.ui.doc_settings:saveSetting(SETTING_KEY, mode)

    -- Individual reveals are page-local and never survive a mode change.
    self.backend:clearPageState()
    self:_applyCss()
end

function FuriganaToggle:onReaderReady()
    self:_applyCss()
    self:_setupTouchZone()
end

function FuriganaToggle:_setupTouchZone()
    if not Device:isTouchDevice() or self._touch_zone_registered then
        return
    end

    self.ui:registerTouchZones({
        {
            id = "furiganatoggle_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = 0,
                ratio_y = 0,
                ratio_w = 1,
                ratio_h = 1,
            },

            -- We must be allowed to see a tap before ordinary page-turn zones.
            -- The handler returns false unless an actual ruby element was hit,
            -- so normal page turning/menu behavior can continue.
            overrides = {
                "tap_forward",
                "tap_backward",
            },

            handler = function(ges)
                if self.mode ~= "toggle" or not ges or not ges.pos then
                    return false
                end
                -- Consume only when a ruby hit was toggled; otherwise allow
                -- normal KOReader tap / page-turn behavior.
                return self.backend:toggleAtScreenPosition(ges.pos)
            end,
        },
    })

    self._touch_zone_registered = true
end

function FuriganaToggle:onPageUpdate(pageno)
    -- pageno is enough as a first page token for paginated CREngine rendering.
    -- If rolling mode needs a more precise token, this is the one place to
    -- replace it with the current visible-page/XPointer identity.
    self.backend:onPageChanged(pageno)
end

function FuriganaToggle:onPosUpdate(pos)
    -- Rolling documents may report position updates instead of discrete pages.
    -- Do NOT clear on every scroll movement: true "page lifetime" semantics
    -- should be connected to the rendered screen/page boundary once verified.
end

function FuriganaToggle:onSaveSettings()
    self.ui.doc_settings:saveSetting(SETTING_KEY, self.mode)
end

function FuriganaToggle:addToMainMenu(menu_items)
    menu_items.furigana_toggle = {
        text = _("Furigana"),
        sorting_hint = "typeset",
        sub_item_table = {
            {
                text = _("Visible"),
                radio = true,
                checked_func = function()
                    return self.mode == "visible"
                end,
                callback = function()
                    self:setMode("visible")
                end,
            },
            {
                text = _("Off"),
                radio = true,
                checked_func = function()
                    return self.mode == "off"
                end,
                callback = function()
                    self:setMode("off")
                end,
            },
            {
                text = _("Toggle"),
                radio = true,
                checked_func = function()
                    return self.mode == "toggle"
                end,
                callback = function()
                    self:setMode("toggle")
                end,
            },
        },
    }
end

function FuriganaToggle:onCloseDocument()
    self.backend:setToggleMode(false)
    self.backend:clearPageState()

    -- Restore ReaderStyleTweak method if this instance still owns the hook.
    local styletweak = self.ui and self.ui.styletweak
    if styletweak and self._css_hook_installed and self._original_getCssText then
        styletweak.getCssText = self._original_getCssText
        self._css_hook_installed = false
    end
end

return FuriganaToggle
