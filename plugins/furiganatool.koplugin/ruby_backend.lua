-- CREngine bridge for Furigana Toggle.
--
-- The Lua plugin is deliberately isolated from engine-specific details here.
-- V1 can use CSS for whole-document modes.
-- True per-ruby toggling requires CREngine to expose element-aware hit testing
-- and a transient visibility override (or an equivalent paint-time mechanism).

local RubyBackend = {}
RubyBackend.__index = RubyBackend

function RubyBackend:new(ui)
    return setmetatable({
        ui = ui,
        revealed = {}, -- xpointer/id -> true, RAM only
        page_token = nil,
    }, self)
end

function RubyBackend:isSupported()
    -- We only target CREngine/reflowable documents.
    return self.ui
        and self.ui.document
        and not self.ui.document.info.has_pages
end

function RubyBackend:clearPageState()
    self.revealed = {}

    -- Future CREngine API:
    -- self.ui.document:clearRubyVisibilityOverrides()
end

function RubyBackend:onPageChanged(page_token)
    if self.page_token ~= page_token then
        self.page_token = page_token
        self:clearPageState()
    end
end

function RubyBackend:getRubyAtScreenPosition(screen_pos)
    -- TODO: CREngine hook.
    --
    -- Desired contract:
    --   local ruby = self.ui.document:getRubyAtPosition(page_pos.x, page_pos.y)
    --
    -- Return:
    --   nil when no ruby base is under the tap
    --   OR a table like:
    --   {
    --       id = "/body/DocFragment[3]/body/p[2]/ruby[4]",
    --       base = "学校",
    --       reading = "がっこう",
    --   }
    --
    -- We intentionally do NOT guess from selected text because KOReader's Lua
    -- layer does not reliably know which source HTML element text came from.
    return nil
end

function RubyBackend:setRubyVisible(ruby_id, visible)
    -- TODO: CREngine hook.
    --
    -- Desired API:
    --   self.ui.document:setRubyVisibilityOverride(ruby_id, visible)
    --
    -- It must NOT trigger reflow in Toggle mode; ruby geometry is reserved.
    return false
end

function RubyBackend:toggleAtScreenPosition(screen_pos)
    local ruby = self:getRubyAtScreenPosition(screen_pos)
    if not ruby then
        return false -- do not consume normal KOReader tap
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

    return true -- consume tap only after a real ruby was toggled
end

return RubyBackend
