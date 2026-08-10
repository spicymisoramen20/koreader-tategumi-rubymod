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
local DITHER_INTENSITY_KEY = "furigana_toggle_dither_intensity"
local FOG_FALLOFF_KEY = "furigana_toggle_fog_falloff"
local FOG_ROUNDNESS_KEY = "furigana_toggle_fog_roundness"
local FOG_PATTERN_KEY = "furigana_toggle_fog_pattern"
local VALID_MODES = {
    visible = true,
    off = true,
    toggle = true,
}
local VALID_OBSCURE = {
    hidden = true,
    bar = true,
    fog = true,
}
local VALID_FOG_PATTERN = {
    bayer8 = true,
    bayer16 = true,
    blue_noise = true,
    checker = true,
    hatch45 = true,
    multi4 = true,
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

    self.dither_intensity = tonumber(self.ui.doc_settings:readSetting(DITHER_INTENSITY_KEY)) or 70
    if self.dither_intensity < 0 then self.dither_intensity = 0 end
    if self.dither_intensity > 100 then self.dither_intensity = 100 end

    self.fog_falloff = tonumber(self.ui.doc_settings:readSetting(FOG_FALLOFF_KEY)) or 4
    self.fog_roundness = tonumber(self.ui.doc_settings:readSetting(FOG_ROUNDNESS_KEY)) or 5
    if self.fog_falloff < 0 then self.fog_falloff = 0 end
    if self.fog_falloff > 64 then self.fog_falloff = 64 end
    if self.fog_roundness < 0 then self.fog_roundness = 0 end
    if self.fog_roundness > 64 then self.fog_roundness = 64 end

    self.fog_pattern = self.ui.doc_settings:readSetting(FOG_PATTERN_KEY) or "bayer8"
    if not VALID_FOG_PATTERN[self.fog_pattern] then
        self.fog_pattern = "bayer8"
    end

    self.backend = RubyBackend:new(self.ui)
    self.backend.obscure_style = self.obscure_style
    self.backend.dither_intensity = self.dither_intensity
    self.backend.fog_falloff = self.fog_falloff
    self.backend.fog_roundness = self.fog_roundness
    self.backend.fog_pattern = self.fog_pattern
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
    self.backend:setDitherParams(self.dither_intensity)
    self.backend:setFogParams(self.fog_falloff, self.fog_roundness, self.fog_pattern)
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
    -- Fog looks best as a light veil; older docs may still have intensity ~70.
    if style == "fog" and self.dither_intensity > 40 then
        self.dither_intensity = 25
        self.ui.doc_settings:saveSetting(DITHER_INTENSITY_KEY, 25)
        self.backend.dither_intensity = 25
        self.backend:_applyDitherParams()
    end
    self.backend:setObscureStyle(style)
end

function FuriganaToggle:setDitherParams(intensity)
    self.dither_intensity = intensity
    self.ui.doc_settings:saveSetting(DITHER_INTENSITY_KEY, intensity)
    self.backend:setDitherParams(intensity)
end

function FuriganaToggle:setFogParams(falloff, roundness, pattern)
    self.fog_falloff = falloff
    self.fog_roundness = roundness
    if pattern and VALID_FOG_PATTERN[pattern] then
        self.fog_pattern = pattern
    end
    self.ui.doc_settings:saveSetting(FOG_FALLOFF_KEY, falloff)
    self.ui.doc_settings:saveSetting(FOG_ROUNDNESS_KEY, roundness)
    self.ui.doc_settings:saveSetting(FOG_PATTERN_KEY, self.fog_pattern)
    self.backend:setFogParams(falloff, roundness, self.fog_pattern)
end

function FuriganaToggle:setFogPattern(pattern)
    if not VALID_FOG_PATTERN[pattern] or pattern == self.fog_pattern then
        return
    end
    self:setFogParams(self.fog_falloff, self.fog_roundness, pattern)
end

function FuriganaToggle:_spinFogParam(which)
    local is_falloff = which == "falloff"
    local spin = SpinWidget:new{
        title_text = is_falloff and _("Fog falloff") or _("Fog roundness"),
        info_text = is_falloff
            and _("Soft edge width in pixels.\nDensity fades to zero over this band.\n0 = hard edge. Typical: 3–8. Allowed: 0–64.")
            or _("Corner radius in pixels for the fog silhouette.\n0 = square corners. Typical: 3–10. Allowed: 0–64."),
        value = is_falloff and self.fog_falloff or self.fog_roundness,
        value_min = 0,
        value_max = 64,
        value_step = 1,
        value_hold_step = 4,
        default_value = is_falloff and 4 or 5,
        ok_always_enabled = true,
        callback = function(spin_widget)
            if is_falloff then
                self:setFogParams(spin_widget.value, self.fog_roundness)
            else
                self:setFogParams(self.fog_falloff, spin_widget.value)
            end
        end,
    }
    UIManager:show(spin)
end

function FuriganaToggle:_spinDitherIntensity()
    local spin = SpinWidget:new{
        title_text = _("Obscure intensity"),
        info_text = _("Approximate % ink in the fog veil (typical 15–35 for B/W dither).\nFor 4-level gray, try 30–60.\nChecker/hatch read denser — lower if needed.\n0 = lightest, 100 = densest."),
        value = self.dither_intensity,
        value_min = 0,
        value_max = 100,
        value_step = 5,
        value_hold_step = 10,
        default_value = 25,
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
    self.ui.doc_settings:saveSetting(DITHER_INTENSITY_KEY, self.dither_intensity)
    self.ui.doc_settings:saveSetting(FOG_FALLOFF_KEY, self.fog_falloff)
    self.ui.doc_settings:saveSetting(FOG_ROUNDNESS_KEY, self.fog_roundness)
    self.ui.doc_settings:saveSetting(FOG_PATTERN_KEY, self.fog_pattern)
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
                    obscure_radio("fog", _("Fog")),
                    {
                        text_func = function()
                            local labels = {
                                bayer8 = _("Bayer 8×8"),
                                bayer16 = _("Bayer 16×16"),
                                blue_noise = _("Blue noise"),
                                checker = _("Checker"),
                                hatch45 = _("45° hatch"),
                                multi4 = _("4-level gray"),
                            }
                            local label = labels[self.fog_pattern] or self.fog_pattern
                            return T(_("Fog pattern: %1"), label)
                        end,
                        enabled_func = function()
                            return self.mode == "toggle"
                                and self.obscure_style == "fog"
                                and self.backend:_hasFogApi()
                        end,
                        sub_item_table_func = function()
                            local function pattern_radio(id, label)
                                return {
                                    text = label,
                                    radio = true,
                                    checked_func = function()
                                        return self.fog_pattern == id
                                    end,
                                    callback = function()
                                        self:setFogPattern(id)
                                    end,
                                }
                            end
                            return {
                                pattern_radio("bayer8", _("Bayer 8×8 (default)")),
                                pattern_radio("bayer16", _("Bayer 16×16 (finer)")),
                                pattern_radio("blue_noise", _("Blue noise (less grid)")),
                                pattern_radio("checker", _("Checker")),
                                pattern_radio("hatch45", _("45° hatch")),
                                pattern_radio("multi4", _("4-level gray (e-ink midtones)")),
                            }
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Fog falloff: %1"), self.fog_falloff)
                        end,
                        enabled_func = function()
                            return self.mode == "toggle"
                                and self.obscure_style == "fog"
                                and self.backend:_hasFogApi()
                        end,
                        keep_menu_open = true,
                        callback = function()
                            self:_spinFogParam("falloff")
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Fog roundness: %1"), self.fog_roundness)
                        end,
                        enabled_func = function()
                            return self.mode == "toggle"
                                and self.obscure_style == "fog"
                                and self.backend:_hasFogApi()
                        end,
                        keep_menu_open = true,
                        callback = function()
                            self:_spinFogParam("roundness")
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Intensity: %1%%"), self.dither_intensity)
                        end,
                        enabled_func = function()
                            return self.mode == "toggle"
                                and self.backend:usesIntensity()
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
