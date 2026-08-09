--[[--
Auto-detects page progression direction (RTL/LTR) from document metadata and
applies it to the reader view when the user has not made an explicit choice.

Supported sources:
- EPUB: `page-progression-direction` attribute on the OPF `<spine>` element
  (stored in document props by crengine's epubfmt.cpp, exposed via cre.cpp)
- CBZ/CBR/CBT: `<ReadingDirection>` element inside ComicInfo.xml

This module is intentionally separate from ReaderView so that upstream
merges to readerview.lua do not conflict with fork-specific detection logic.
The module runs its onReadSettings *after* ReaderView (registered later), so
view state set by ReaderView is already available.
]]

local BD = require("ui/bidi")
local EventListener = require("ui/widget/eventlistener")
local Notification = require("ui/widget/notification")
local _ = require("gettext")

local ReaderAutoDirection = EventListener:extend{}

function ReaderAutoDirection:onReadSettings(config)
    -- "direction_auto_detected" is written the first time we successfully detect
    -- a direction for this document.  Once set, we defer entirely to whatever
    -- inverse_reading_order the user (or the previous auto-run) left behind.
    -- This avoids re-detecting on every open while still letting the user override.
    if config:has("direction_auto_detected") then return end

    -- Global RTL default already in effect – nothing to do.
    if self.view.inverse_reading_order then return end

    local ok, PageDirection = pcall(require, "util/page_direction")
    if not ok then return end

    local dir = PageDirection.getDirection(self.document)

    -- Mark detection as done regardless of outcome so we don't re-scan on
    -- every open (the result is stored in inverse_reading_order itself).
    config:saveSetting("direction_auto_detected", dir or "none")

    if dir ~= "rtl" then return end

    -- Apply RTL reading order and keep the progress bar in sync.
    -- ReaderView:onReadSettings ran first and set the bar for the non-detected
    -- value; re-apply now to reflect the auto-detected reading order.
    self.view.inverse_reading_order = not BD.mirroredUILayout()
    self.view:setupTouchZones()
    self:_syncProgressBar()
    Notification:notify(_("RTL page order detected – switching automatically."))
end

-- Recompute and apply the combined progress-bar inversion.
-- Called after auto-detection so the bar reflects the updated reading order.
-- Delegates to ReaderView's single helper so the inversion logic (mirrored UI /
-- RTL reading order / vertical-rl) lives in exactly one place.
function ReaderAutoDirection:_syncProgressBar()
    self.view:syncProgressBarDirection()
end

return ReaderAutoDirection
