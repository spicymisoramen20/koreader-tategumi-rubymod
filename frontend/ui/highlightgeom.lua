--[[--
Shared highlight geometry (ReaderView + CreHtmlBoxWidget footnote popup).
--]]

local HighlightGeom = {}

-- Breathing room past the base/em band, on the side *away* from ruby/fog.
-- The annotation-facing edge stays on the getRect band so Lighten does not
-- eat the furigana gap (same rule for vertical-rl and horizontal-tb).
HighlightGeom.CROSS_PAD_PX = 4

--- Expand a screen-space Lighten/Invert rect away from ruby/fog.
-- Vertical-rl: grow left (after); keep right (before / fog).
-- Horizontal-tb: grow down; keep top (ruby-position:over / fog).
function HighlightGeom.padAwayFromAnnotation(x, y, w, h, is_vertical)
    local pad = HighlightGeom.CROSS_PAD_PX
    if is_vertical then
        return x - pad, y, w + pad, h
    end
    return x, y, w, h + pad
end

return HighlightGeom
