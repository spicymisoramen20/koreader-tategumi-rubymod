--[[--
Page progression direction detector for automatic RTL/LTR reading order.

Supports:
- EPUB: reads `page-progression-direction` from OPF spine directly via the
  ZIP archive (bypasses crengine cache entirely — reliable on first open)
- CBZ/CBR/CBT: reads `<ReadingDirection>` from ComicInfo.xml inside the archive

Both formats are handled via ffi/archiver (libarchive), so no C++ changes
are required and the detection is cache-independent.
]]

local logger = require("logger")
local M = {}

-- ── helpers ──────────────────────────────────────────────────────────────

local function openArchiveReader(filepath)
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not ok then return nil end
    local reader = Archiver.Reader:new()
    if not reader:open(filepath) then return nil end
    return reader
end

-- ── ComicInfo.xml (CBZ/CBR) ──────────────────────────────────────────────

local function parseComicInfo(xml)
    if not xml then return nil end
    local dir = xml:match("<ReadingDirection>%s*(%a+)%s*</ReadingDirection>")
    return dir and (dir:upper() == "RTL" and "rtl" or "ltr") or nil
end

local function directionFromComicInfo(filepath)
    local reader = openArchiveReader(filepath)
    if not reader then return nil end
    local direction
    for entry in reader:iterate() do
        if entry.mode == "file" then
            local lp = entry.path:lower()
            if lp == "comicinfo.xml" or lp:match("/comicinfo%.xml$") then
                direction = parseComicInfo(reader:extractToMemory(entry.path))
                break
            end
        end
    end
    reader:close()
    return direction
end

-- ── EPUB OPF ─────────────────────────────────────────────────────────────

-- Extract the OPF root-file path from META-INF/container.xml content.
local function opfPathFromContainer(xml)
    if not xml then return nil end
    return xml:match('full%-path="([^"]+)"')
end

-- Extract page-progression-direction from OPF content.
local function ppdFromOPF(xml)
    if not xml then return nil end
    -- Match the <spine> element (possibly with many attributes).
    local spine = xml:match("<spine[^>]*>") or xml:match("<spine[^/]*/?>")
    if not spine then return nil end
    local ppd = spine:match('page%-progression%-direction="(%a+)"')
    if not ppd then return nil end
    ppd = ppd:lower()
    return (ppd == "rtl" or ppd == "ltr") and ppd or nil
end

local function directionFromEpub(filepath)
    local reader = openArchiveReader(filepath)
    if not reader then return nil end

    -- Step 1: find container.xml to locate the OPF.
    local opf_path
    for entry in reader:iterate() do
        if entry.mode == "file" then
            local lp = entry.path:lower()
            if lp == "meta-inf/container.xml" then
                local xml = reader:extractToMemory(entry.path)
                opf_path = opfPathFromContainer(xml)
                break
            end
        end
    end
    if not opf_path then
        reader:close()
        logger.dbg("PageDirection: no container.xml found in", filepath)
        return nil
    end

    -- Step 2: read the OPF and extract page-progression-direction.
    local direction
    -- extractToMemory can seek; try by path key first.
    local xml = reader:extractToMemory(opf_path)
    if not xml then
        -- Path lookup may be case-sensitive; scan all entries.
        local lp_target = opf_path:lower()
        for entry in reader:iterate() do
            if entry.mode == "file" and entry.path:lower() == lp_target then
                xml = reader:extractToMemory(entry.path)
                break
            end
        end
    end
    direction = ppdFromOPF(xml)
    reader:close()
    logger.dbg("PageDirection: EPUB", filepath, "→", direction)
    return direction
end

-- ── public API ───────────────────────────────────────────────────────────

-- Return the page progression direction for a document file.
-- @param document  A document instance (must expose .file path).
-- @return "rtl", "ltr", or nil (direction unknown / not specified).
function M.getDirection(document)
    if not document or not document.file then return nil end
    local ext = document.file:match("%.(%w+)$")
    if not ext then return nil end
    ext = ext:lower()

    if ext == "epub" or ext == "epub3" then
        return directionFromEpub(document.file)
    elseif ext == "cbz" or ext == "cbr" or ext == "cbt" then
        return directionFromComicInfo(document.file)
    end

    return nil
end

return M
