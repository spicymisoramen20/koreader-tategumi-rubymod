-- CSS fragments owned by this plugin.
--
-- IMPORTANT:
-- "toggle" intentionally reserves ruby layout space.
-- Which hiding method CREngine handles best should be tested on-device.
-- visibility:hidden is the preferred CSS-semantic behavior; if CREngine's
-- ruby implementation does not preserve the annotation box with it, the
-- backend can later hide ruby at paint time instead.
local Styles = {}

Styles.visible = ""

Styles.off = [[
rt, rp {
    display: none !important;
}
]]

Styles.toggle = [[
/*
 * Toggle mode keeps ruby fully laid out.
 * Per-ruby visibility is now handled at CREngine paint time.
 */
rp {
    display: none !important;
}
]]

return Styles
