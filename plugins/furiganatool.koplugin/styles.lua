local Styles = {}

-------------------------------------------------------------------------------
-- Visible
-------------------------------------------------------------------------------

Styles.visible = [[
/*
 * Furigana visible normally.
 */
]]

-------------------------------------------------------------------------------
-- Off
--
-- Ruby annotations are completely removed from layout.
-------------------------------------------------------------------------------

Styles.off = [[
rt {
    display: none !important;
}

rp {
    display: none !important;
}
]]

-------------------------------------------------------------------------------
-- Toggle
--
-- IMPORTANT:
--
-- Do NOT use:
--
--     visibility: hidden
--
-- here.
--
-- Toggle visibility is handled by CREngine at paint time.
-- This leaves all original ruby geometry/layout intact.
-------------------------------------------------------------------------------

Styles.toggle = [[
rp {
    display: none !important;
}
]]

return Styles
