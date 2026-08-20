local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")

-- Typeset → Vertical layout: column-top alignment for vertical-rl.
--
-- Print-faithful mode applies CSS text-indent as a first-column offset
-- (段首), so continuation columns sit higher than paragraph-start columns.
-- Uniform mode keeps every column flush to the same top.
-- Indent strength scales that first-column offset (print-faithful only).

local MODE_UNIFORM = "uniform"
local MODE_INDENT = "indent"
local DEFAULT_MODE = MODE_INDENT
local DEFAULT_SCALE = 100

local ReaderVerticalLayout = WidgetContainer:extend{
    column_top_mode = DEFAULT_MODE,
    text_indent_scale = DEFAULT_SCALE,
}

function ReaderVerticalLayout:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderVerticalLayout:_modeInt()
    return self.column_top_mode == MODE_UNIFORM and 0 or 1
end

function ReaderVerticalLayout:_applyPrefs(rerender)
    if not self.ui.document or not self.ui.document.setVertColumnTopPrefs then
        return
    end
    self.ui.document:setVertColumnTopPrefs(self:_modeInt(), self.text_indent_scale)
    if rerender then
        -- Prefs are part of calcGlobalSettingsHash, so UpdatePos re-renders
        -- the same way as hanging punctuation / font size.
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
end

function ReaderVerticalLayout:_setMode(mode, rerender)
    if mode ~= MODE_UNIFORM then
        mode = MODE_INDENT
    end
    self.column_top_mode = mode
    self:_applyPrefs(rerender)
end

function ReaderVerticalLayout:_setScale(scale, rerender)
    scale = tonumber(scale) or DEFAULT_SCALE
    if scale < 0 then
        scale = 0
    elseif scale > 100 then
        scale = 100
    end
    self.text_indent_scale = math.floor(scale)
    self:_applyPrefs(rerender)
end

function ReaderVerticalLayout:_readMode(config)
    local mode = config and config:readSetting("vertical_column_top_mode")
        or G_reader_settings:readSetting("vertical_column_top_mode")
        or DEFAULT_MODE
    if mode ~= MODE_UNIFORM then
        mode = MODE_INDENT
    end
    return mode
end

function ReaderVerticalLayout:_readScale(config)
    local scale = config and config:readSetting("vertical_text_indent_scale")
        or G_reader_settings:readSetting("vertical_text_indent_scale")
        or DEFAULT_SCALE
    scale = tonumber(scale) or DEFAULT_SCALE
    if scale < 0 then
        scale = 0
    elseif scale > 100 then
        scale = 100
    end
    return math.floor(scale)
end

function ReaderVerticalLayout:onReadSettings(config)
    self.column_top_mode = self:_readMode(config)
    self.text_indent_scale = self:_readScale(config)
    self:_applyPrefs()
end

function ReaderVerticalLayout:onPreRenderDocument()
    -- Re-apply immediately before the first render so Format() sees the prefs.
    self:_applyPrefs()
end

function ReaderVerticalLayout:onSaveSettings()
    self.ui.doc_settings:saveSetting("vertical_column_top_mode", self.column_top_mode)
    self.ui.doc_settings:saveSetting("vertical_text_indent_scale", self.text_indent_scale)
end

function ReaderVerticalLayout:_makeDefaultMode()
    local current_default = G_reader_settings:readSetting("vertical_column_top_mode") or DEFAULT_MODE
    local indent_is_default = current_default ~= MODE_UNIFORM
    UIManager:show(MultiConfirmBox:new{
        text = _("Would you like to use uniform column tops or first-column indent by default for vertical text?\n\nThe current default (★) is shown below."),
        choice1_text_func = function()
            return indent_is_default and _("Align uniformly") or _("Align uniformly (★)")
        end,
        choice1_callback = function()
            G_reader_settings:saveSetting("vertical_column_top_mode", MODE_UNIFORM)
        end,
        choice2_text_func = function()
            return indent_is_default and _("Indent first column (★)") or _("Indent first column")
        end,
        choice2_callback = function()
            G_reader_settings:saveSetting("vertical_column_top_mode", MODE_INDENT)
        end,
    })
end

function ReaderVerticalLayout:_spinIndentScale(touchmenu_instance)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = _("First-column indent"),
        info_text = _("How strong the first-column indent is, as a percentage of the book's text-indent.\n100% is print-faithful. Lower values keep 段首 but reduce the staircase at the top margin. 0% matches uniform column tops.\nTap the number to type any value from 0 to 100."),
        value = self.text_indent_scale,
        value_min = 0,
        value_max = 100,
        value_step = 1,
        value_hold_step = 10,
        unit = "%",
        default_value = G_reader_settings:readSetting("vertical_text_indent_scale") or DEFAULT_SCALE,
        ok_always_enabled = true,
        callback = function(spin)
            self:_setScale(spin.value, true)
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
        extra_text = _("Set as default"),
        extra_callback = function(spin)
            local scale = tonumber(spin.value) or DEFAULT_SCALE
            G_reader_settings:saveSetting("vertical_text_indent_scale", scale)
        end,
    })
end

function ReaderVerticalLayout:addToMainMenu(menu_items)
    menu_items.vertical_layout = {
        text = _("Vertical layout"),
        help_text = _([[Column-top alignment for vertical (tategumi) text.

Indent first column keeps Japanese 段首: the first column of a paragraph starts lower than continuation columns.

Align uniformly keeps every column flush to the same top.

First-column indent scales that 段首 offset when indent is enabled.]]),
        sub_item_table = {
            {
                text = _("Align column tops uniformly"),
                help_text = _("Every column starts at the same top. Paragraph indent, if any, no longer shifts the whole column down."),
                checked_func = function()
                    return self.column_top_mode == MODE_UNIFORM
                end,
                radio = true,
                callback = function()
                    self:_setMode(MODE_UNIFORM, true)
                end,
                hold_callback = function()
                    self:_makeDefaultMode()
                end,
            },
            {
                text = _("Indent first column (print style)"),
                help_text = _("The first column of each paragraph is indented (段首). Columns that continue a paragraph stay flush to the top."),
                checked_func = function()
                    return self.column_top_mode == MODE_INDENT
                end,
                radio = true,
                callback = function()
                    self:_setMode(MODE_INDENT, true)
                end,
                hold_callback = function()
                    self:_makeDefaultMode()
                end,
            },
            {
                text_func = function()
                    return T(_("First-column indent: %1 %"), self.text_indent_scale)
                end,
                enabled_func = function()
                    return self.column_top_mode == MODE_INDENT
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:_spinIndentScale(touchmenu_instance)
                end,
                hold_callback = function()
                    G_reader_settings:saveSetting("vertical_text_indent_scale", self.text_indent_scale)
                    UIManager:show(InfoMessage:new{
                        text = T(_("Default first-column indent set to %1%."), self.text_indent_scale),
                        timeout = 2,
                    })
                end,
            },
        },
    }
end

return ReaderVerticalLayout
