--[[--
Vertical-rl inline image placement regression.

Small gaiji images embedded in vertical text reserve the correct inline space,
but used to be drawn near the top of the column because the image branch
clamped Y against the column width instead of using the formatted word->x.

Detection is log-style, via C++ diagnostics:
  draw_count   > 0  confirms the fixture hit the vertical inline-image branch.
  drift_count == 0  confirms draw Y == y + frmline->x + clamped word->x.
--]]

local lfs = require("libs/libkoreader-lfs")

describe("Vertical text: inline image placement", function()
    local epub_path = "spec/front/unit/data/fixtures/vertical_text/inline_image_test.epub"
    local DocumentRegistry, ReaderUI, Screen, UIManager
    local readerui, doc

    setup(function()
        require("commonrequire")
        disable_plugins()
        require("document/canvascontext"):init(require("device"))
        DocumentRegistry = require("document/documentregistry")
        ReaderUI         = require("apps/reader/readerui")
        Screen           = require("device").screen
        UIManager        = require("ui/uimanager")
    end)

    after_each(function()
        if readerui then
            readerui:onClose()
            readerui = nil
        end
    end)

    it("draws inline images at their formatted column-depth position #inline_image", function()
        if not lfs.attributes(epub_path) then
            pending("inline_image_test.epub fixture missing")
            return
        end

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(epub_path),
        }
        doc = readerui.document
        doc._document:resetVertImageDrawDrift()

        UIManager:show(readerui)
        fastforward_ui_events()
        readerui.rolling:onGotoPage(1)
        fastforward_ui_events()

        local draw_count, drift_count, max_px = doc._document:getVertImageDrawDrift()
        print(string.format("[inline_image] draw_count=%d drift_count=%d max_px=%d",
            draw_count, drift_count, max_px))

        assert.is_true(draw_count > 0, "fixture did not draw a vertical inline image")
        assert.are.equal(0, drift_count,
            string.format("vertical inline image draw Y drifted from layout position (worst: %d px)", max_px))
    end)
end)
