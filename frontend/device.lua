local util = require("ffi/util")
local Version = require("version")

local function probeDevice()
    local platform = Version:getCurrentPlatform()
    if platform then
        if platform:sub(1, #"android") == "android" then
            return require("device/android/device")
        elseif platform:sub(1, #"cervantes") == "cervantes" then
            return require("device/cervantes/device")
        elseif platform:sub(1, #"kindle") == "kindle" then
            return require("device/kindle/device")
        elseif platform:sub(1, #"kobo") == "kobo" then
            return require("device/kobo/device")
        elseif platform:sub(1, #"pocketbook") == "pocketbook" then
            return require("device/pocketbook/device")
        elseif platform:sub(1, #"sony-prstux") == "sony-prstux" then
            return require("device/sony-prstux/device")
        end
    end
<<<<<<< HEAD

    local kindle_test_stat = lfs.attributes("/proc/usid")
    if kindle_test_stat then
        return require("device/kindle/device")
    end

    local kobo_test_stat = lfs.attributes("/bin/kobo_config.sh")
    if kobo_test_stat then
        return require("device/kobo/device")
    end

    local pbook_test_stat = lfs.attributes("/ebrmain")
    if pbook_test_stat then
        return require("device/pocketbook/device")
    end

    local remarkable_test_stat = lfs.attributes("/usr/bin/xochitl")
    if remarkable_test_stat then
        return require("device/remarkable/device")
    end

    local sony_prstux_test_stat = lfs.attributes("/etc/PRSTUX")
    if sony_prstux_test_stat then
        return require("device/sony-prstux/device")
    end

    local cervantes_test_stat = lfs.attributes("/usr/bin/ntxinfo")
    if cervantes_test_stat then
        return require("device/cervantes/device")
    end

    -- add new ports here:
    --
    -- if --[[ implement a proper test instead --]] false then
    --     return require("device/newport/device")
    -- end

=======
>>>>>>> upstream/master
    if util.loadSDL3() then
        return require("device/sdl/device")
    end
    error("Could not find hardware abstraction for this platform. If you are trying to run the emulator, please ensure SDL is installed.")
end

local dev = probeDevice()
dev:init()
return dev
