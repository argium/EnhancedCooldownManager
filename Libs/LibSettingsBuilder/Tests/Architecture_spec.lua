-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

describe("LibSettingsBuilder architecture", function()
    local function collectLibraryLuaFiles()
        local files = {}
        local handle = assert(io.popen("find Libs/LibSettingsBuilder -type f -name '*.lua' | sort"))
        for path in handle:lines() do
            if not path:find("/Tests/", 1, true) then
                files[#files + 1] = path
            end
        end
        handle:close()
        return files
    end

    local function readCode(path)
        local file = assert(io.open(path, "r"))
        local text = file:read("*a")
        file:close()
        return text:gsub("%-%-[^\n]*", "")
    end

    it("keeps direct Blizzard UI/API calls inside Interop", function()
        local globals = {
            "Settings",
            "SettingsPanel",
            "CreateFrame",
            "CreateSettings",
            "CreateColorFromHexString",
            "StaticPopup",
            "GameTooltip",
            "GameTooltip_Hide",
            "hooksecurefunc",
            "MinimalSliderWithSteppersMixin",
            "ScrollUtil",
            "CreateDataProvider",
            "CreateScrollBoxListLinearView",
        }

        for _, path in ipairs(collectLibraryLuaFiles()) do
            local text = readCode(path)
            if not path:find("/Interop/", 1, true) then
                for _, global in ipairs(globals) do
                    assert.is_nil(
                        text:find("%f[%w_]" .. global .. "%f[^%w_]", 1),
                        path .. " must not reference Blizzard global " .. global
                    )
                end
            end
        end
    end)

    it("keeps Interop from calling higher layers", function()
        for _, path in ipairs(collectLibraryLuaFiles()) do
            if path:find("/Interop/", 1, true) then
                local text = readCode(path)
                assert.is_nil(text:find("internal%.builders", 1, true), path .. " must not call builders")
                assert.is_nil(text:find("internal%.registry", 1, true), path .. " must not call registry")
                assert.is_nil(text:find("%f[%w_]builders%."), path .. " must not call builders")
                assert.is_nil(text:find("%f[%w_]registry%."), path .. " must not call registry")
            end
        end
    end)

    it("keeps builders from calling registry or Blizzard directly", function()
        local globals = {
            "Settings",
            "SettingsPanel",
            "CreateFrame",
            "StaticPopup",
            "GameTooltip",
            "hooksecurefunc",
        }

        for _, path in ipairs(collectLibraryLuaFiles()) do
            if path:find("/Builders/", 1, true) then
                local text = readCode(path)
                assert.is_nil(text:find("internal%.registry", 1, true), path .. " must not import registry through internal")
                for _, global in ipairs(globals) do
                    assert.is_nil(
                        text:find("%f[%w_]" .. global .. "%f[^%w_]", 1),
                        path .. " must not reference Blizzard global " .. global
                    )
                end
            end
        end
    end)

    it("keeps lib table exports public-only", function()
        local allowed = {
            New = true,
            GetSection = true,
            GetRootPage = true,
            GetPage = true,
            HasCategory = true,
        }

        for _, path in ipairs(collectLibraryLuaFiles()) do
            local text = readCode(path)
            for name in text:gmatch("function%s+lib[%.:]([A-Za-z_][A-Za-z0-9_]*)") do
                assert.is_true(allowed[name], path .. " exports unexpected lib method " .. name)
            end
        end
    end)
end)
