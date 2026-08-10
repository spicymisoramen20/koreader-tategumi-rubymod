local Device = require("device")
local Event = require("ui/event")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local Styles = require("styles")
local RubyBackend = require("ruby_backend")

local FuriganaToggle = WidgetContainer:extend{
    name = "furiganatoggle",
    is_doc_only = true,
}

local SETTING_KEY = "furigana_toggle_mode"
local OBSCURE_SETTING_KEY = "furigana_toggle_obscure"
local BLUR_RADIUS_KEY = "furigana_toggle_blur_radius"
local BLUR_PASSES_KEY = "furigana_toggle_blur_passes"
local DITHER_INTENSITY_KEY = "furigana_toggle_dither_intensity"
local VALID_MODES = {
    visible = true,
    off = true,
    toggle = true,
}
local VALID_OBSCURE = {
    hidden = true,
    bar = true,
    blur = true,
    dissolve = true,
    bayer2 = true,
    bayer4 = true,
    bayer8 = true,
    checker = true,
    hatch = true,
    noise = true,
}

function FuriganaToggle:init()
    self.mode = self.ui.doc_settings:readSetting(SETTING_KEY) or "visible"
    if not VALID_MODES[self.mode] then
        self.mode = "visible"
    end

    self.obscure_style = self.ui.doc_settings:readSetting(OBSCURE_SETTING_KEY) or "hidden"
    if not VALID_OBSCURE[self.obscure_style] then
        self.obscure_style = "hidden"
        self.ui.doc_settings:saveSetting(OBSCURE_SETTING_KEY, self.obscure_style)
    end

    self.blur_radius = tonumber(self.ui.doc_settings:readSetting(BLUR_RADIUS_KEY)) or 2
    self.blur_passes = tonumber(self.ui.doc_settings:readSetting(BLUR_PASSES_KEY)) or 2
    if self.blur_radius < 0 then self.blur_radius = 0 end
    if self.blur_radius > 64 then self.blur_radius = 64 end
    if self.blur_passes < 1 then self.blur_passes = 1 end
    if self.blur_passes > 20 then self.blur_passes = 20 end

    self.dither_intensity = tonumber(self.ui.doc_settings:readSetting(DITHER_INTENSITY_KEY)) or 70
    if self.dither_intensity < 0 then self.dither_intensity = 0 end
    if self.dither_intensity > 100 then self.dither_intensity = 100 end

    self.backend = RubyBackend:new(self.ui)
    self.backend.obscure_style = self.obscure_style
    self.backend.blur_radius = self.blur_radius
    self.backend.blur_passes = self.blur_passes
    self.backend.dither_intensity = self.dither_intensity
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

    self.backend:setObscureStyle(self.obscure_style)
    self.backend:setBlurParams(self.blur_radius, self.blur_passes)
    self.backend:setDitherParams(self.dither_intensity)
    self.backend:setToggleMode(self.mode == "toggle")

    self.ui:handleEvent(Event:new("ApplyStyleSheet"))
end

function FuriganaToggle:setMode(mode)
    if not VALID_MODES[mode] or mode == self.mode then
        return
    end

    self.mode = mode
    self.ui.doc_settings:saveSetting(SETTING_KEY, mode)
    self.backend:clearRevealedState()
    self:_applyCss()
end

function FuriganaToggle:setObscureStyle(style)
    if not VALID_OBSCURE[style] or style == self.obscure_style then
        return
    end

    self.obscure_style = style
    self.ui.doc_settings:saveSetting(OBSCURE_SETTING_KEY, style)
    self.backend:setObscureStyle(style)
end

function FuriganaToggle:setBlurParams(radius, passes)
    self.blur_radius = radius
    self.blur_passes = passes
    self.ui.doc_settings:saveSetting(BLUR_RADIUS_KEY, radius)
    self.ui.doc_settings:saveSetting(BLUR_PASSES_KEY, passes)
    self.backend:setBlurParams(radius, passes)
end

function FuriganaToggle:setDitherParams(intensity)
    self.dither_intensity = intensity
    self.ui.doc_settings:saveSetting(DITHER_INTENSITY_KEY, intensity)
    self.backend:setDitherParams(intensity)
end

function FuriganaToggle:_spinBlurParam(which)
    local is_radius = which == "radius"
    local spin = SpinWidget:new{
        title_text = is_radius and _("Blur radius") or _("Blur passes"),
        info_text = is_radius
            and _("Box-blur kernel radius in pixels.\nTypical: 1–4. Allowed: 0–64.")
            or _("How many times to apply the blur.\nTypical: 1–3. Allowed: 1–20."),
        value = is_radius and self.blur_radius or self.blur_passes,
        value_min = is_radius and 0 or 1,
        value_max = is_radius and 64 or 20,
        value_step = 1,
        value_hold_step = is_radius and 4 or 2,
        default_value = 2,
        ok_always_enabled = true,
        callback = function(spin_widget)
            if is_radius then
                self:setBlurParams(spin_widget.value, self.blur_passes)
            else
                self:setBlurParams(self.blur_radius, spin_widget.value)
            end
        end,
    }
    UIManager:show(spin)
end

function FuriganaToggle:_spinDitherIntensity()
    local spin = SpinWidget:new{
        title_text = _("Obscure intensity"),
        info_text = _("How strongly dissolve/dither removes furigana ink.\n0 = fully readable, 100 = fully hidden.\nTypical: 55–80."),
        value = self.dither_intensity,
        value_min = 0,
        value_max = 100,
        value_step = 5,
        value_hold_step = 10,
        default_value = 70,
        ok_always_enabled = true,
        callback = function(spin_widget)
            self:setDitherParams(spin_widget.value)
        end,
    }
    UIManager:show(spin)
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
            overrides = {
                "tap_forward",
                "tap_backward",
            },
            handler = function(ges)
                if self.mode ~= "toggle" or not ges or not ges.pos then
                    return false
                end
                return self.backend:toggleAtScreenPosition(ges.pos)
            end,
        },
    })

    self._touch_zone_registered = true
end

function FuriganaToggle:onPageUpdate(pageno)
    self.backend:onPageChanged(pageno)
end

function FuriganaToggle:onPosUpdate(pos)
end

function FuriganaToggle:onSaveSettings()
    self.ui.doc_settings:saveSetting(SETTING_KEY, self.mode)
    self.ui.doc_settings:saveSetting(OBSCURE_SETTING_KEY, self.obscure_style)
    self.ui.doc_settings:saveSetting(BLUR_RADIUS_KEY, self.blur_radius)
    self.ui.doc_settings:saveSetting(BLUR_PASSES_KEY, self.blur_passes)
    self.ui.doc_settings:saveSetting(DITHER_INTENSITY_KEY, self.dither_intensity)
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
                    obscure_radio("bar", _("Bar")),
                    obscure_radio("blur", _("Blur")),
                    {
                        text_func = function()
                            return T(_("Blur radius: %1"), self.blur_radius)
                        end,
                        enabled_func = function()
                            return self.mode == "toggle"
                                and self.obscure_style == "blur"
                                and self.backend:_hasBlurApi()
                        end,
                        keep_menu_open = true,
                        callback = function()
                            self:_spinBlurParam("radius")
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Blur passes: %1"), self.blur_passes)
                        end,
                        enabled_func = function()
                            return self.mode == "toggle"
                                and self.obscure_style == "blur"
                                and self.backend:_hasBlurApi()
                        end,
                        keep_menu_open = true,
                        callback = function()
                            self:_spinBlurParam("passes")
                        end,
                    },
                    obscure_radio("dissolve", _("Dissolve")),
                    obscure_radio("bayer4", _("Bayer 4×4")),
                    obscure_radio("bayer2", _("Bayer 2×2")),
                    obscure_radio("bayer8", _("Bayer 8×8")),
                    obscure_radio("checker", _("Checker")),
                    obscure_radio("hatch", _("Hatch")),
                    obscure_radio("noise", _("Noise")),
                    {
                        text_func = function()
                            return T(_("Intensity: %1%%"), self.dither_intensity)
                        end,
                        enabled_func = function()
                            return self.mode == "toggle"
                                and self.backend:isDitherStyle(self.obscure_style)
                                and self.backend:_hasDitherApi()
                        end,
                        keep_menu_open = true,
                        callback = function()
                            self:_spinDitherIntensity()
                        end,
                    },
                },
            },
        },
    }
end

function FuriganaToggle:onCloseDocument()
    self.backend:setToggleMode(false)
    self.backend:clearRevealedState()

    local styletweak = self.ui and self.ui.styletweak
    if styletweak and self._css_hook_installed and self._original_getCssText then
        styletweak.getCssText = self._original_getCssText
        self._css_hook_installed = false
    end
end

return FuriganaToggle
