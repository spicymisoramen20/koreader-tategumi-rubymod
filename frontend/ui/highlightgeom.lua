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

--- Force every rect to the same content-band height, centered on the source mid-Y.
-- Bottom-aligning taller drag-select unions shifted the bar down vs word holds;
-- preserving mid-Y keeps long-press and drag optically aligned. Same-line
-- fragments also share one mid so multi-box lines stay level.
function HighlightGeom.normalizeHorizontalBandHeight(rects, band_h)
    if not rects or #rects == 0 or not band_h or band_h < 1 then
        return rects
    end

    local clusters = {}
    for _, r in ipairs(rects) do
        local mid = r.y + r.h / 2
        local placed = false
        for _, c in ipairs(clusters) do
            if math.abs(mid - c.mid) <= math.max(band_h, r.h) * 0.6 then
                table.insert(c.rects, r)
                c.mid_sum = c.mid_sum + mid
                c.n = c.n + 1
                c.mid = c.mid_sum / c.n
                placed = true
                break
            end
        end
        if not placed then
            table.insert(clusters, {
                rects = { r },
                mid_sum = mid,
                n = 1,
                mid = mid,
            })
        end
    end

    for _, c in ipairs(clusters) do
        local y = math.floor(c.mid - band_h / 2)
        for _, r in ipairs(c.rects) do
            r.y = y
            r.h = band_h
        end
    end
    return rects
end

return HighlightGeom
