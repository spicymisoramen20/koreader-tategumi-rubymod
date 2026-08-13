--[[--
Shared highlight geometry (ReaderView + CreHtmlBoxWidget footnote popup).
--]]

local HighlightGeom = {}

-- Book ReaderView (vertical + horizontal rolling): breathing room past the
-- base/em band on both cross-axis sides.
HighlightGeom.CROSS_PAD_PX = 4

-- CRE footnote popup only (always horizontal-tb). Smaller than the book pad so
-- Lighten does not look oversized next to compact footnote type.
HighlightGeom.FOOTNOTE_CROSS_PAD_PX = 2

--- Expand a screen-space Lighten/Invert rect symmetrically on the cross axis.
-- @tparam number|nil pad_px Override (e.g. FOOTNOTE_CROSS_PAD_PX); default CROSS_PAD_PX.
function HighlightGeom.padCrossAxis(x, y, w, h, is_vertical, pad_px)
    local pad = pad_px or HighlightGeom.CROSS_PAD_PX
    if is_vertical then
        return x - pad, y, w + 2 * pad, h
    end
    return x, y - pad, w, h + 2 * pad
end

--- Force every rect to the same content-band height (bottom-aligned).
-- Footnote ruby vs plain getRect bands can differ; normalize before pad/paint
-- so long-press and drag Lighten match.
function HighlightGeom.normalizeHorizontalBandHeight(rects, band_h)
    if not rects or not band_h or band_h < 1 then
        return rects
    end
    for _, r in ipairs(rects) do
        local bottom = r.y + r.h
        r.h = band_h
        r.y = bottom - band_h
    end
    return rects
end

return HighlightGeom
