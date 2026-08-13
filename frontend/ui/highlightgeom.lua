--[[--
Shared highlight geometry (ReaderView + CreHtmlBoxWidget footnote popup).
--]]

local HighlightGeom = {}

-- Breathing room past the base/em band on *both* cross-axis sides so Lighten
-- stays centered on the glyphs (vertical: width; horizontal: height).
-- Annotation/fog clearance comes from getRect's base-only band, not from
-- skipping the annotation-side pad (that un-centered horizontal highlights).
HighlightGeom.CROSS_PAD_PX = 4

--- Expand a screen-space Lighten/Invert rect symmetrically on the cross axis.
function HighlightGeom.padCrossAxis(x, y, w, h, is_vertical)
    local pad = HighlightGeom.CROSS_PAD_PX
    if is_vertical then
        return x - pad, y, w + 2 * pad, h
    end
    return x, y - pad, w, h + 2 * pad
end

return HighlightGeom
