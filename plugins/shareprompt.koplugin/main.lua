--[[--
Reusable prompt templates for sharing selected text.

@module koplugin.SharePrompt
--]]--

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Notification = require("ui/widget/notification")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local SELECTION_PLACEHOLDER = "{{selection}}"
local SAMPLE_SELECTION = _("[selected text]")

local SharePrompt = WidgetContainer:extend{
    name = "shareprompt",
    is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/shareprompt.lua",
}

local function defaultPrompts()
    return {
        {
            id = "explain",
            name = _("Explain"),
            template = _("Explain the following text clearly and concisely:\n\n{{selection}}"),
        },
        {
            id = "translate",
            name = _("Translate"),
            template = _("Translate the following text to English:\n\n{{selection}}"),
        },
    }
end

function SharePrompt:init()
    self:loadSettings()
    self.ui.menu:registerToMainMenu(self)
    if self.document and self.ui.highlight then
        self:addToHighlightDialog()
    end
end

function SharePrompt:loadSettings()
    self.settings = LuaSettings:open(self.settings_file)
    self.prompts = self.settings:readSetting("prompts")
    if type(self.prompts) ~= "table" or #self.prompts == 0 then
        self.prompts = defaultPrompts()
        self.settings:saveSetting("prompts", self.prompts)
        self.updated = true
    end
    self.last_prompt_id = self.settings:readSetting("last_prompt_id")
end

function SharePrompt:saveSettings()
    self.settings:saveSetting("prompts", self.prompts)
    self.settings:saveSetting("last_prompt_id", self.last_prompt_id)
    self.updated = true
end

function SharePrompt:onFlushSettings()
    if self.updated then
        self.settings:flush()
        self.updated = nil
    end
end

function SharePrompt:newPromptId()
    return tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

function SharePrompt:getPromptById(id)
    if not id then return nil end
    for _, prompt in ipairs(self.prompts) do
        if prompt.id == id then
            return prompt
        end
    end
end

function SharePrompt:getDefaultPrompt()
    local last = self:getPromptById(self.last_prompt_id)
    if last then
        return last
    end
    return self.prompts[1]
end

--- Fill a template with selected text. Uses {{selection}} when present;
-- otherwise appends the selection after a blank line.
function SharePrompt.fillTemplate(template, selection)
    template = template or ""
    selection = selection or ""
    if template:find(SELECTION_PLACEHOLDER, 1, true) then
        local parts = {}
        local start = 1
        while true do
            local i, j = template:find(SELECTION_PLACEHOLDER, start, true)
            if not i then
                table.insert(parts, template:sub(start))
                break
            end
            table.insert(parts, template:sub(start, i - 1))
            table.insert(parts, selection)
            start = j + 1
        end
        return table.concat(parts)
    end
    if template == "" then
        return selection
    end
    if selection == "" then
        return template
    end
    return template .. "\n\n" .. selection
end

function SharePrompt:addToHighlightDialog()
    -- Sort near Search / QR (keys are alphabetical; keep 12_search last when possible).
    self.ui.highlight:addToHighlightDialog("12_share_prompt", function(this)
        return {
            text = _("Share with prompt"),
            callback = function()
                local text = util.cleanupSelectedText(this.selected_text and this.selected_text.text or "")
                this:onClose(true)
                self:showSharePreview(text, this)
            end,
        }
    end)
end

function SharePrompt:showSharePreview(selection_text, highlight)
    if #self.prompts == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No prompts yet. Add one from the Share prompts menu."),
        })
        return
    end

    local prompt = self:getDefaultPrompt()
    local preview
    local filled

    local function refreshPreview()
        filled = SharePrompt.fillTemplate(prompt.template, selection_text)
        if preview then
            preview.text = filled
            preview.title = T(_("Share with prompt: %1"), prompt.name)
            preview:reinit()
        end
    end

    local function finishHighlight()
        if highlight then
            UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), function()
                if highlight.clear then
                    highlight:clear()
                end
            end)
        end
    end

    local function doCopy()
        if not Device:hasClipboard() then
            UIManager:show(InfoMessage:new{
                text = _("Clipboard is not available on this device."),
            })
            return
        end
        Device.input.setClipboardText(filled)
        UIManager:show(Notification:new{
            text = _("Prompt copied to clipboard."),
        })
        UIManager:close(preview)
    end

    local function doShare()
        if Device:canShareText() then
            local action = _("Share with prompt")
            UIManager:close(preview)
            Device:doShareText(filled, action, prompt.name)
        else
            doCopy()
        end
    end

    local function showPromptPicker()
        local picker
        local buttons = {}
        for _, p in ipairs(self.prompts) do
            local chosen = p
            table.insert(buttons, {{
                text = p.name,
                callback = function()
                    UIManager:close(picker)
                    prompt = chosen
                    self.last_prompt_id = prompt.id
                    self:saveSettings()
                    refreshPreview()
                end,
            }})
        end
        table.insert(buttons, {{
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(picker)
            end,
        }})
        picker = ButtonDialog:new{
            title = _("Select prompt"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(picker)
    end

    filled = SharePrompt.fillTemplate(prompt.template, selection_text)
    local buttons = {
        {
            {
                text = _("Select prompt"),
                callback = showPromptPicker,
            },
        },
        {
            {
                text = _("Share"),
                enabled = Device:canShareText() or Device:hasClipboard(),
                callback = doShare,
            },
            {
                text = _("Copy"),
                enabled = Device:hasClipboard(),
                callback = doCopy,
            },
        },
    }

    preview = TextViewer:new{
        title = T(_("Share with prompt: %1"), prompt.name),
        title_multilines = true,
        text = filled,
        text_type = "lookup",
        justified = false,
        buttons_table = buttons,
        close_callback = finishHighlight,
    }
    UIManager:show(preview)
end

function SharePrompt:addToMainMenu(menu_items)
    menu_items.share_prompt = {
        text = _("Share prompts"),
        sorting_hint = "more_tools",
        sub_item_table_func = function()
            return self:getManagerMenuItems()
        end,
    }
end

function SharePrompt:getManagerMenuItems()
    local items = {
        {
            text = _("New prompt"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:editPrompt(nil, touchmenu_instance)
            end,
            separator = true,
        },
    }
    for _, prompt in ipairs(self.prompts) do
        local p = prompt
        table.insert(items, {
            text = p.name,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:editPrompt(p, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                self:showPromptActions(p, touchmenu_instance)
            end,
        })
    end
    if #self.prompts == 0 then
        table.insert(items, {
            text = _("(no prompts yet)"),
            enabled = false,
        })
    end
    return items
end

function SharePrompt:showPromptActions(prompt, touchmenu_instance)
    local dialog
    dialog = ButtonDialog:new{
        buttons = {
            {
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(dialog)
                        self:editPrompt(prompt, touchmenu_instance)
                    end,
                },
            },
            {
                {
                    text = _("Preview"),
                    callback = function()
                        UIManager:close(dialog)
                        self:previewPrompt(prompt)
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(dialog)
                        self:confirmDeletePrompt(prompt, touchmenu_instance)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function SharePrompt:previewPrompt(prompt)
    local filled = SharePrompt.fillTemplate(prompt.template, SAMPLE_SELECTION)
    UIManager:show(TextViewer:new{
        title = T(_("Preview: %1"), prompt.name),
        text = filled,
        text_type = "lookup",
        justified = false,
    })
end

function SharePrompt:confirmDeletePrompt(prompt, touchmenu_instance)
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete prompt %1?"), prompt.name),
        ok_text = _("Delete"),
        ok_callback = function()
            self:deletePrompt(prompt)
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    })
end

function SharePrompt:deletePrompt(prompt)
    for i, p in ipairs(self.prompts) do
        if p.id == prompt.id then
            table.remove(self.prompts, i)
            break
        end
    end
    if self.last_prompt_id == prompt.id then
        self.last_prompt_id = self.prompts[1] and self.prompts[1].id or nil
    end
    self:saveSettings()
end

function SharePrompt:editPrompt(prompt, touchmenu_instance)
    local is_new = prompt == nil
    local name_dialog
    name_dialog = InputDialog:new{
        title = is_new and _("New prompt") or _("Edit prompt name"),
        input = prompt and prompt.name or "",
        input_hint = _("Prompt name"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(name_dialog)
                    end,
                },
                {
                    text = _("Next"),
                    is_enter_default = true,
                    callback = function()
                        local name = util.trim(name_dialog:getInputText() or "")
                        if name == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter a prompt name."),
                            })
                            return
                        end
                        UIManager:close(name_dialog)
                        self:editPromptTemplate(prompt, name, is_new, touchmenu_instance)
                    end,
                },
            },
        },
    }
    UIManager:show(name_dialog)
    name_dialog:onShowKeyboard()
end

function SharePrompt:editPromptTemplate(prompt, name, is_new, touchmenu_instance)
    local template_dialog
    template_dialog = InputDialog:new{
        title = T(_("Prompt: %1"), name),
        input = prompt and prompt.template or (SELECTION_PLACEHOLDER .. "\n"),
        input_hint = T(_("Use %1 where selected text should appear"), SELECTION_PLACEHOLDER),
        allow_newline = true,
        fullscreen = true,
        condensed = true,
        add_nav_bar = true,
        cursor_at_end = false,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(template_dialog)
                    end,
                },
                {
                    text = _("Preview"),
                    callback = function()
                        self:previewPrompt({
                            name = name,
                            template = template_dialog:getInputText() or "",
                        })
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local template = template_dialog:getInputText() or ""
                        if is_new then
                            local new_prompt = {
                                id = self:newPromptId(),
                                name = name,
                                template = template,
                            }
                            table.insert(self.prompts, new_prompt)
                            self.last_prompt_id = new_prompt.id
                        else
                            prompt.name = name
                            prompt.template = template
                        end
                        self:saveSettings()
                        UIManager:close(template_dialog)
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(template_dialog)
    template_dialog:onShowKeyboard()
end

return SharePrompt
