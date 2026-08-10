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
local OBSCURE_SETTING_KEY = "furigana_toggle_obscure"
local VALID_MODES = {
    visible = true,
    off = true,
    toggle = true,
}
local VALID_OBSCURE = {
    hidden = true,
    mosaic = true,
    bar = true,
    dots = true,
}

function FuriganaToggle:init()
    self.mode = self.ui.doc_settings:readSetting(SETTING_KEY) or "visible"
    if not VALID_MODES[self.mode] then
        self.mode = "visible"
    end

    self.obscure_style = self.ui.doc_settings:readSetting(OBSCURE_SETTING_KEY) or "hidden"
    if not VALID_OBSCURE[self.obscure_style] then
        self.obscure_style = "hidden"
    end

    self.backend = RubyBackend:new(self.ui)
    self.backend.obscure_style = self.obscure_style
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
    self.backend:setObscureStyle(self.obscure_style)
    self.backend:setToggleMode(self.mode == "toggle")

    -- Full stylesheet apply shows the CRE loading bar (expected once on mode
    -- change). Tap reveal/hide must never reach this path.
    self.ui:handleEvent(Event:new("ApplyStyleSheet"))
end

function FuriganaToggle:setMode(mode)
    if not VALID_MODES[mode] or mode == self.mode then
        return
    end

    self.mode = mode
    self.ui.doc_settings:saveSetting(SETTING_KEY, mode)

    -- Reveals never survive a mode change.
    self.backend:clearRevealedState()
    self:_applyCss()
end

function FuriganaToggle:setObscureStyle(style)
    if not VALID_OBSCURE[style] or style == self.obscure_style then
        return
    end

    self.obscure_style = style
    self.ui.doc_settings:saveSetting(OBSCURE_SETTING_KEY, style)
    -- Paint-only: no stylesheet apply / no loading bar.
    self.backend:setObscureStyle(style)
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
    -- Revealed furigana persist across page turns while Toggle stays active.
    self.backend:onPageChanged(pageno)
end

function FuriganaToggle:onPosUpdate(pos)
    -- Do not clear on scroll/position updates.
end

function FuriganaToggle:onSaveSettings()
    self.ui.doc_settings:saveSetting(SETTING_KEY, self.mode)
    self.ui.doc_settings:saveSetting(OBSCURE_SETTING_KEY, self.obscure_style)
end

function FuriganaToggle:addToMainMenu(menu_items)
    local function obscure_radio(id, label)
        return {
            text = label,
            radio = true,
            enabled_func = function()
                return self.mode == "toggle" and self.backend:isSupported()
                    and self.backend:_hasObscureApi()
            end,
            checked_func = function()
                return self.obscure_style == id
            end,
            callback = function()
                self:setObscureStyle(id)
            end,
        }
    end

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
            {
                text = _("Toggle hide style"),
                separator = true,
                sub_item_table = {
                    obscure_radio("hidden", _("Hidden")),
                    obscure_radio("mosaic", _("Mosaic")),
                    obscure_radio("bar", _("Bar")),
                    obscure_radio("dots", _("Dots")),
                },
            },
        },
    }
end

function FuriganaToggle:onCloseDocument()
    self.backend:setToggleMode(false)
    self.backend:clearRevealedState()

    -- Restore ReaderStyleTweak method if this instance still owns the hook.
    local styletweak = self.ui and self.ui.styletweak
    if styletweak and self._css_hook_installed and self._original_getCssText then
        styletweak.getCssText = self._original_getCssText
        self._css_hook_installed = false
    end
end

return FuriganaToggle
