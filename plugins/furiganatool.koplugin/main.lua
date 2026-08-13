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
local LEVEL_SETTING_KEY = "furigana_toggle_level_scheme"
local DITHER_INTENSITY_KEY = "furigana_toggle_dither_intensity"
local FOG_FALLOFF_KEY = "furigana_toggle_fog_falloff"
local FOG_ROUNDNESS_KEY = "furigana_toggle_fog_roundness"
local AUTO_HIDE_KEY = "furigana_toggle_auto_hide_sec"
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
local VALID_LEVEL = {
    off = true,
    jlpt = true,
    joyo = true,
    kanken = true,
}

local DEFAULT_INTENSITY = 10
local DEFAULT_FALLOFF = 5
local DEFAULT_ROUNDNESS = 15
local DEFAULT_AUTO_HIDE_SEC = 1
local AUTO_HIDE_MIN_SEC = 0.1
local AUTO_HIDE_MAX_SEC = 60

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

    self.level_scheme = self.ui.doc_settings:readSetting(LEVEL_SETTING_KEY) or "off"
    if not VALID_LEVEL[self.level_scheme] then
        self.level_scheme = "off"
        self.ui.doc_settings:saveSetting(LEVEL_SETTING_KEY, self.level_scheme)
    end

    self.dither_intensity = tonumber(self.ui.doc_settings:readSetting(DITHER_INTENSITY_KEY)) or DEFAULT_INTENSITY
    if self.dither_intensity < 0 then self.dither_intensity = 0 end
    if self.dither_intensity > 100 then self.dither_intensity = 100 end

    self.fog_falloff = tonumber(self.ui.doc_settings:readSetting(FOG_FALLOFF_KEY)) or DEFAULT_FALLOFF
    self.fog_roundness = tonumber(self.ui.doc_settings:readSetting(FOG_ROUNDNESS_KEY)) or DEFAULT_ROUNDNESS
    if self.fog_falloff < 0 then self.fog_falloff = 0 end
    if self.fog_falloff > 64 then self.fog_falloff = 64 end
    if self.fog_roundness < 0 then self.fog_roundness = 0 end
    if self.fog_roundness > 64 then self.fog_roundness = 64 end

    self.auto_hide_sec = tonumber(self.ui.doc_settings:readSetting(AUTO_HIDE_KEY)) or 0
    if self.auto_hide_sec < 0 then self.auto_hide_sec = 0 end
    if self.auto_hide_sec > AUTO_HIDE_MAX_SEC then self.auto_hide_sec = AUTO_HIDE_MAX_SEC end
    -- Treat tiny positives as off; SpinWidget min is AUTO_HIDE_MIN_SEC when enabling.
    if self.auto_hide_sec > 0 and self.auto_hide_sec < AUTO_HIDE_MIN_SEC then
        self.auto_hide_sec = AUTO_HIDE_MIN_SEC
    end
    self._auto_hide_tasks = {}

    -- One-shot: Soft gray is the only Fog fill now. Drop legacy pattern
    -- settings and adopt the new falloff/roundness/intensity defaults.
    local FOG_SOFT_DEFAULTS_KEY = "furigana_toggle_fog_soft_defaults_v1"
    if self.ui.doc_settings:readSetting(FOG_SOFT_DEFAULTS_KEY) ~= true then
        self.ui.doc_settings:delSetting("furigana_toggle_fog_pattern")
        self.dither_intensity = DEFAULT_INTENSITY
        self.fog_falloff = DEFAULT_FALLOFF
        self.fog_roundness = DEFAULT_ROUNDNESS
        self.ui.doc_settings:saveSetting(DITHER_INTENSITY_KEY, DEFAULT_INTENSITY)
        self.ui.doc_settings:saveSetting(FOG_FALLOFF_KEY, DEFAULT_FALLOFF)
        self.ui.doc_settings:saveSetting(FOG_ROUNDNESS_KEY, DEFAULT_ROUNDNESS)
        self.ui.doc_settings:saveSetting(FOG_SOFT_DEFAULTS_KEY, true)
    end

    self.backend = RubyBackend:new(self.ui)
    self.backend.obscure_style = self.obscure_style
    self.backend.level_scheme = self.level_scheme
    self.backend.dither_intensity = self.dither_intensity
    self.backend.fog_falloff = self.fog_falloff
    self.backend.fog_roundness = self.fog_roundness
    -- Install CSS text early so any later styletweak pull includes it.
    -- ApplyStyleSheet itself is deferred to postReaderReady (UpdatePos is a
    -- no-op while ReaderUI:init is still running).
    self._plugin_css = Styles[self.mode] or ""
    self:_installCssInjection()

    -- Stable aliases for other modules (directory name is furiganatool).
    self.ui.furigana = self
    if self.ui.highlight then
        self.ui.highlight._furigana_plugin = self
    end

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
    self.backend:setLevelScheme(self.level_scheme)
    self.backend:setDitherParams(self.dither_intensity)
    self.backend:setFogParams(self.fog_falloff, self.fog_roundness)
    self.backend:setToggleMode(self.mode == "toggle")

    self.ui:handleEvent(Event:new("ApplyStyleSheet"))
    -- First-open highlight boxes can be computed before this reflow settles;
    -- drop any cached screen geometry so the next paint recomputes.
    if self.ui.view and self.ui.view.resetHighlightBoxesCache then
        self.ui.view:resetHighlightBoxesCache()
    end
end

function FuriganaToggle:setMode(mode)
    if not VALID_MODES[mode] or mode == self.mode then
        return
    end

    self:_cancelAllAutoHide()
    self.mode = mode
    self.ui.doc_settings:saveSetting(SETTING_KEY, mode)
    self.backend:clearRevealedState()
    self:_applyCss()
end

function FuriganaToggle:_autoHideEnabled()
    return self.mode == "toggle"
        and self.auto_hide_sec
        and self.auto_hide_sec >= AUTO_HIDE_MIN_SEC
end

function FuriganaToggle:setAutoHide(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 0 then seconds = 0 end
    if seconds > AUTO_HIDE_MAX_SEC then seconds = AUTO_HIDE_MAX_SEC end
    if seconds > 0 and seconds < AUTO_HIDE_MIN_SEC then
        seconds = AUTO_HIDE_MIN_SEC
    end
    -- Round to 0.1 s so stored values match the spin step.
    if seconds > 0 then
        seconds = math.floor(seconds * 10 + 0.5) / 10
    end
    self.auto_hide_sec = seconds
    self.ui.doc_settings:saveSetting(AUTO_HIDE_KEY, seconds)
    if not self:_autoHideEnabled() then
        self:_cancelAllAutoHide()
    end
end

function FuriganaToggle:_formatAutoHideSec(seconds)
    seconds = tonumber(seconds) or 0
    if seconds == math.floor(seconds) then
        return string.format("%d", seconds)
    end
    return string.format("%.1f", seconds)
end

function FuriganaToggle:_cancelAutoHideForIds(ids)
    if not ids or not self._auto_hide_tasks then
        return
    end
    for _, id in ipairs(ids) do
        local task = self._auto_hide_tasks[id]
        if task then
            UIManager:unschedule(task)
            self._auto_hide_tasks[id] = nil
        end
    end
end

function FuriganaToggle:_cancelAllAutoHide()
    if not self._auto_hide_tasks then
        self._auto_hide_tasks = {}
        return
    end
    for id, task in pairs(self._auto_hide_tasks) do
        UIManager:unschedule(task)
        self._auto_hide_tasks[id] = nil
    end
end

function FuriganaToggle:_scheduleAutoHide(ids)
    if not self:_autoHideEnabled() or not ids or #ids == 0 then
        return
    end

    self:_cancelAutoHideForIds(ids)
    local delay = self.auto_hide_sec
    for _, id in ipairs(ids) do
        local ruby_id = id
        local task
        task = function()
            if self._auto_hide_tasks[ruby_id] ~= task then
                return
            end
            self._auto_hide_tasks[ruby_id] = nil
            if not self:_autoHideEnabled() or not self.backend then
                return
            end
            if self.backend.revealed[ruby_id] then
                self.backend:setRubyGroupVisible({ ruby_id }, false)
            end
        end
        self._auto_hide_tasks[ruby_id] = task
        UIManager:scheduleIn(delay, task)
    end
end

function FuriganaToggle:toggleRubyIds(ids)
    if not self.backend or not ids or #ids == 0 then
        return false
    end

    local revealing = false
    for _, id in ipairs(ids) do
        if not self.backend.revealed[id] then
            revealing = true
            break
        end
    end

    local ok = self.backend:toggleRubyIds(ids)
    if not ok then
        return false
    end

    if revealing then
        self:_scheduleAutoHide(ids)
    else
        self:_cancelAutoHideForIds(ids)
    end
    return true
end

function FuriganaToggle:toggleAtScreenPosition(screen_pos)
    if self.mode ~= "toggle" or not self.backend then
        return false
    end
    local ruby = self.backend:getRubyAtScreenPosition(screen_pos)
    if not ruby or not ruby.ids then
        return false
    end
    return self:toggleRubyIds(ruby.ids)
end

function FuriganaToggle:_spinAutoHide(touchmenu_instance)
    local spin = SpinWidget:new{
        title_text = _("Auto-hide delay"),
        info_text = _("Automatically hide revealed furigana after this many seconds.\nFractions are allowed (e.g. 0.3).\nDisable turns auto-hide off."),
        value = self:_autoHideEnabled() and self.auto_hide_sec or DEFAULT_AUTO_HIDE_SEC,
        value_min = AUTO_HIDE_MIN_SEC,
        value_max = AUTO_HIDE_MAX_SEC,
        value_step = 0.1,
        value_hold_step = 1,
        precision = "%.1f",
        unit = "s",
        default_value = DEFAULT_AUTO_HIDE_SEC,
        ok_text = _("Set"),
        ok_always_enabled = true,
        cancel_text = _("Disable"),
        cancel_callback = function()
            self:setAutoHide(0)
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
        callback = function(spin_widget)
            self:setAutoHide(spin_widget.value)
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }
    UIManager:show(spin)
end

function FuriganaToggle:setObscureStyle(style)
    if not VALID_OBSCURE[style] or style == self.obscure_style then
        return
    end

    self.obscure_style = style
    self.ui.doc_settings:saveSetting(OBSCURE_SETTING_KEY, style)
    self.backend:setObscureStyle(style)
end

function FuriganaToggle:setLevelScheme(scheme)
    if not VALID_LEVEL[scheme] or scheme == self.level_scheme then
        return
    end

    self.level_scheme = scheme
    self.ui.doc_settings:saveSetting(LEVEL_SETTING_KEY, scheme)
    self.backend:setLevelScheme(scheme)
end

function FuriganaToggle:setDitherParams(intensity)
    self.dither_intensity = intensity
    self.ui.doc_settings:saveSetting(DITHER_INTENSITY_KEY, intensity)
    self.backend:setDitherParams(intensity)
end

function FuriganaToggle:setFogParams(falloff, roundness)
    self.fog_falloff = falloff
    self.fog_roundness = roundness
    self.ui.doc_settings:saveSetting(FOG_FALLOFF_KEY, falloff)
    self.ui.doc_settings:saveSetting(FOG_ROUNDNESS_KEY, roundness)
    self.backend:setFogParams(falloff, roundness)
end

function FuriganaToggle:_spinFogParam(which)
    local is_falloff = which == "falloff"
    local spin = SpinWidget:new{
        title_text = is_falloff and _("Fog falloff") or _("Fog roundness"),
        info_text = is_falloff
            and _("Soft edge width in pixels.\nDensity fades to zero over this band.\n0 = hard edge. Typical: 3–8. Allowed: 0–64.")
            or _("Corner radius in pixels for the fog silhouette.\n0 = square corners. Typical: 3–15. Allowed: 0–64."),
        value = is_falloff and self.fog_falloff or self.fog_roundness,
        value_min = 0,
        value_max = 64,
        value_step = 1,
        value_hold_step = 4,
        default_value = is_falloff and DEFAULT_FALLOFF or DEFAULT_ROUNDNESS,
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
        info_text = _("Approximate % ink in the fog veil.\nSoft gray midtones — typical 5–25.\n0 = lightest, 100 = densest."),
        value = self.dither_intensity,
        value_min = 0,
        value_max = 100,
        value_step = 5,
        value_hold_step = 10,
        default_value = DEFAULT_INTENSITY,
        ok_always_enabled = true,
        callback = function(spin_widget)
            self:setDitherParams(spin_widget.value)
        end,
    }
    UIManager:show(spin)
end

function FuriganaToggle:onReaderReady()
    -- ApplyStyleSheet → UpdatePos is ignored while postReaderReadyCallback is
    -- still set. Prepend so setStyleSheet runs before ReaderRolling's
    -- updatePos() (registered in Rolling:init); that updatePos then sees the
    -- new rendering hash and reflows.
    table.insert(self.ui.postReaderReadyCallback, 1, function()
        self:_applyCss()
    end)
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
                return self:toggleAtScreenPosition(ges.pos)
            end,
        },
    })

    self._touch_zone_registered = true
end

-- Button for ReaderHighlight's edit dialog. Targets only the ruby under
-- screen_pos (the finger tap that opened the dialog), not every ruby in the
-- highlight range.
function FuriganaToggle:buildHighlightDialogButton(annotation, on_done, screen_pos)
    if self.mode ~= "toggle" or not self.backend then
        return nil
    end
    if not annotation or type(annotation.pos0) ~= "string" then
        return nil
    end

    -- Ensure engine toggle flag is on if the UI mode says so.
    if not self.backend.toggle_mode then
        self.backend:setToggleMode(true)
    end

    local function resolve_ids_at_tap()
        if not screen_pos then
            return {}
        end
        local ruby = self.backend:getRubyAtScreenPosition(screen_pos)
        if ruby and ruby.ids and #ruby.ids > 0 then
            return ruby.ids
        end
        -- Modest finger fudge around the tap (base glyph ↔ fog sit side by
        -- side in vertical-rl). Still returns at most one ruby group.
        local Device = require("device")
        local step = Device.screen:scaleBySize(14)
        local ox, oy = screen_pos.x, screen_pos.y
        for _, d in ipairs({
            { step, 0 }, { -step, 0 }, { 0, step }, { 0, -step },
            { 2 * step, 0 }, { -2 * step, 0 },
        }) do
            ruby = self.backend:getRubyAtScreenPosition({ x = ox + d[1], y = oy + d[2] })
            if ruby and ruby.ids and #ruby.ids > 0 then
                return ruby.ids
            end
        end
        return {}
    end

    local ids = resolve_ids_at_tap()
    if #ids == 0 then
        return nil
    end

    local any_hidden = false
    for _, id in ipairs(ids) do
        if not self.backend.revealed[id] then
            any_hidden = true
            break
        end
    end

    local Notification = require("ui/widget/notification")
    return {
        text = any_hidden and _("Show furigana") or _("Hide furigana"),
        callback = function()
            if on_done then
                on_done()
            end
            local live_ids = resolve_ids_at_tap()
            if not live_ids or #live_ids == 0 then
                Notification:notify(_("No furigana under finger"))
                return
            end
            self:toggleRubyIds(live_ids)
        end,
    }
end

function FuriganaToggle:onPageUpdate(pageno)
    self.backend:onPageChanged(pageno)
end

function FuriganaToggle:onPosUpdate(pos)
end

function FuriganaToggle:onSaveSettings()
    self.ui.doc_settings:saveSetting(SETTING_KEY, self.mode)
    self.ui.doc_settings:saveSetting(OBSCURE_SETTING_KEY, self.obscure_style)
    self.ui.doc_settings:saveSetting(LEVEL_SETTING_KEY, self.level_scheme)
    self.ui.doc_settings:saveSetting(DITHER_INTENSITY_KEY, self.dither_intensity)
    self.ui.doc_settings:saveSetting(FOG_FALLOFF_KEY, self.fog_falloff)
    self.ui.doc_settings:saveSetting(FOG_ROUNDNESS_KEY, self.fog_roundness)
    self.ui.doc_settings:saveSetting(AUTO_HIDE_KEY, self.auto_hide_sec or 0)
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

    local function level_radio(id, label)
        return {
            text = label,
            radio = true,
            enabled_func = function()
                return self.mode == "toggle" and self.backend:isSupported()
                    and self.backend:_hasLevelApi()
            end,
            checked_func = function()
                return self.level_scheme == id
            end,
            callback = function()
                self:setLevelScheme(id)
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
                text_func = function()
                    if self:_autoHideEnabled() then
                        return T(_("Auto-hide: %1 s"), self:_formatAutoHideSec(self.auto_hide_sec))
                    end
                    return _("Auto-hide")
                end,
                checked_func = function()
                    return self:_autoHideEnabled()
                end,
                enabled_func = function()
                    return self.mode == "toggle" and self.backend:isSupported()
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:_spinAutoHide(touchmenu_instance)
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
                    {
                        text = _("Kanji level label"),
                        separator = true,
                        sub_item_table = {
                            level_radio("off", _("Off")),
                            level_radio("jlpt", _("JLPT")),
                            level_radio("joyo", _("Joyo (常用)")),
                            level_radio("kanken", _("Kanken (漢検)")),
                        },
                    },
                },
            },
        },
    }
end

function FuriganaToggle:onCloseDocument()
    self:_cancelAllAutoHide()
    self.backend:setToggleMode(false)
    self.backend:clearRevealedState()

    local styletweak = self.ui and self.ui.styletweak
    if styletweak and self._css_hook_installed and self._original_getCssText then
        styletweak.getCssText = self._original_getCssText
        self._css_hook_installed = false
    end
end

return FuriganaToggle
