--[[--
HTML snippet widget with vertical scroll bar, rendered via CREngine.
Mirrors ScrollHtmlWidget's surface API for FootnoteWidget.
--]]

local BD = require("ui/bidi")
local CreHtmlBoxWidget = require("ui/widget/crehtmlboxwidget")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalScrollBar = require("ui/widget/verticalscrollbar")
local Input = Device.input
local Screen = Device.screen

local ScrollCreHtmlWidget = InputContainer:extend{
    html_body = nil,
    css = nil,
    default_font_size = Screen:scaleBySize(24),
    font_face = nil,
    htmlbox_widget = nil,
    v_scroll_bar = nil,
    dialog = nil,
    html_link_tapped_callback = nil,
    dimen = nil,
    width = 0,
    height = 0,
    scroll_bar_width = Screen:scaleBySize(6),
    text_scroll_span = Screen:scaleBySize(12),
    -- Furigana parity (passed through to CreHtmlBoxWidget)
    furigana_toggle_mode = "visible",
    furigana_toggle_obscure = "hidden",
    furigana_toggle_dither_intensity = 10,
    furigana_toggle_fog_falloff = 5,
    furigana_toggle_fog_roundness = 15,
}

function ScrollCreHtmlWidget:init()
    self.htmlbox_widget = CreHtmlBoxWidget:new{
        dimen = Geom:new{
            w = self.width - self.scroll_bar_width - self.text_scroll_span,
            h = self.height,
        },
        dialog = self.dialog,
        html_link_tapped_callback = self.html_link_tapped_callback,
        furigana_toggle_mode = self.furigana_toggle_mode,
        furigana_toggle_obscure = self.furigana_toggle_obscure,
        furigana_toggle_dither_intensity = self.furigana_toggle_dither_intensity,
        furigana_toggle_fog_falloff = self.furigana_toggle_fog_falloff,
        furigana_toggle_fog_roundness = self.furigana_toggle_fog_roundness,
    }

    self.htmlbox_widget:setContent(self.html_body, self.css, self.default_font_size, self.font_face)

    self.v_scroll_bar = VerticalScrollBar:new{
        enable = self.htmlbox_widget.page_count > 1,
        width = self.scroll_bar_width,
        height = self.height,
        scroll_callback = function(ratio)
            self:scrollToRatio(ratio)
        end
    }

    self:_updateScrollBar()

    local horizontal_group = HorizontalGroup:new{}
    table.insert(horizontal_group, self.htmlbox_widget)
    table.insert(horizontal_group, HorizontalSpan:new{ width = self.text_scroll_span })
    table.insert(horizontal_group, self.v_scroll_bar)
    self[1] = horizontal_group

    self.dimen = Geom:new(self[1]:getSize())

    if Device:isTouchDevice() then
        self.ges_events = {
            ScrollText = {
                GestureRange:new{
                    ges = "swipe",
                    range = function() return self.dimen end,
                },
            },
            TapScrollText = {
                GestureRange:new{
                    ges = "tap",
                    range = function() return self.dimen end,
                },
            },
        }
    end

    if Device:hasKeys() then
        self.key_events = {
            ScrollDown = { { Input.group.PgFwd } },
            ScrollUp = { { Input.group.PgBack } },
        }
    end
end

function ScrollCreHtmlWidget:_updateScrollBar(draw)
    local count = math.max(self.htmlbox_widget.page_count, 1)
    local low = (self.htmlbox_widget.page_number - 1) / count
    local high = self.htmlbox_widget.page_number / count
    self.v_scroll_bar:set(low, high)
    if draw then
        UIManager:setDirty(self, function()
            return "partial", self.v_scroll_bar.dimen
        end)
    end
    if self.scroll_callback then
        self.scroll_callback(low, high)
    end
end

function ScrollCreHtmlWidget:getSinglePageHeight()
    return self.htmlbox_widget:getSinglePageHeight()
end

function ScrollCreHtmlWidget:getCurrentRatio()
    local count = math.max(self.htmlbox_widget.page_count, 1)
    return (self.htmlbox_widget.page_number - 1) / count
end

function ScrollCreHtmlWidget:resetScroll()
    self.htmlbox_widget:setPageNumber(1)
    self:_updateScrollBar()
    self.v_scroll_bar.enable = self.htmlbox_widget.page_count > 1
end

function ScrollCreHtmlWidget:scrollToRatio(ratio)
    ratio = math.max(0, math.min(1, ratio))
    local count = math.max(self.htmlbox_widget.page_count, 1)
    local page_num = 1 + math.floor(count * ratio)
    if page_num > count then
        page_num = count
    end
    if page_num == self.htmlbox_widget.page_number then
        return
    end
    self.htmlbox_widget:setPageNumber(page_num)
    self:_updateScrollBar()
    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()

    if self.dialog.movable and self.dialog.movable.alpha then
        self.dialog.movable.alpha = nil
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dialog.movable.dimen
        end)
    else
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dimen
        end)
    end
end

function ScrollCreHtmlWidget:scrollText(direction)
    if direction == 0 then
        return
    end

    if direction > 0 then
        if self.htmlbox_widget.page_number >= self.htmlbox_widget.page_count then
            return
        end
        self.htmlbox_widget:setPageNumber(self.htmlbox_widget.page_number + 1)
    elseif direction < 0 then
        if self.htmlbox_widget.page_number <= 1 then
            return
        end
        self.htmlbox_widget:setPageNumber(self.htmlbox_widget.page_number - 1)
    end
    self:_updateScrollBar()
    self.htmlbox_widget:freeBb()
    self.htmlbox_widget:_render()

    if self.dialog.movable and self.dialog.movable.alpha then
        self.dialog.movable.alpha = nil
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dialog.movable.dimen
        end)
    else
        UIManager:setDirty(self.dialog, function()
            return "partial", self.dimen
        end)
    end
end

function ScrollCreHtmlWidget:onScrollText(arg, ges)
    if ges.direction == "north" then
        self:scrollText(1)
        return true
    elseif ges.direction == "south" then
        self:scrollText(-1)
        return true
    end
end

function ScrollCreHtmlWidget:onTapScrollText(arg, ges)
    if self.ignore_taps then return false end
    -- Prefer furigana toggle taps on the CRE box when Toggle mode is active.
    if self.htmlbox_widget.furigana_toggle_mode == "toggle" then
        local handled = self.htmlbox_widget:onTapText(arg, ges)
        if handled then
            return true
        end
    end
    if BD.flipIfMirroredUILayout(ges.pos.x < Screen:getWidth()/2) then
        return self:onScrollUp()
    else
        return self:onScrollDown()
    end
end

function ScrollCreHtmlWidget:setTapScrollEnabled(enabled)
    self.ignore_taps = not enabled
end

function ScrollCreHtmlWidget:onScrollUp()
    if self.htmlbox_widget.page_number > 1 then
        self:scrollText(-1)
        return true
    end
end

function ScrollCreHtmlWidget:onScrollDown()
    if self.htmlbox_widget.page_number < self.htmlbox_widget.page_count then
        self:scrollText(1)
        return true
    end
end

function ScrollCreHtmlWidget:scrollToTop()
    self:scrollToRatio(0)
end

function ScrollCreHtmlWidget:scrollToBottom()
    self:scrollToRatio(1)
end

return ScrollCreHtmlWidget
