-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

if type(describe) ~= "function" or type(it) ~= "function" then
    return
end

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("Utilities", function()
    local originalGlobals
    local addonNS

    local function newFontStringSpy()
        local spy = {
            setFontCalls = {},
            shadowColorCalls = {},
            shadowOffsetCalls = {},
        }

        function spy:SetFont(path, size, outline)
            self.setFontCalls[#self.setFontCalls + 1] = {
                path = path,
                size = size,
                outline = outline,
            }
        end

        function spy:SetShadowColor(r, g, b, a)
            self.shadowColorCalls[#self.shadowColorCalls + 1] = {
                r = r, g = g, b = b, a = a,
            }
        end

        function spy:SetShadowOffset(x, y)
            self.shadowOffsetCalls[#self.shadowOffsetCalls + 1] = {
                x = x, y = y,
            }
        end

        return spy
    end

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM",
            "LibStub",
            "ECM_debug_assert",
            "issecretvalue",
            "issecrettable",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.ECM = {}
        _G.LibStub = function(name)
            if name == "LibSharedMedia-3.0" then
                return {
                    Fetch = function(_, mediaType, key)
                        if mediaType == "font" and type(key) == "string" then
                            return "FONT:" .. key
                        end
                        return nil
                    end,
                }
            end
            return nil
        end
        _G.ECM.DebugAssert = function() end
        _G.issecretvalue = function() return false end
        _G.issecrettable = function() return false end

        addonNS = {
            Addon = {
                db = {
                    profile = {
                        global = {
                            font = "Global Font",
                            fontSize = 11,
                            fontOutline = "OUTLINE",
                            fontShadow = false,
                        },
                    },
                },
            },
        }

        local constantsChunk = TestHelpers.loadChunk(
            {
                "Constants.lua",
                "../Constants.lua",
            },
            "Unable to load Constants.lua"
        )
        constantsChunk()

        local utilitiesChunk = TestHelpers.loadChunk(
            {
                "Modules/Utilities.lua",
                "../Modules/Utilities.lua",
            },
            "Unable to load Modules/Utilities.lua"
        )
        utilitiesChunk(nil, addonNS)
    end)

    it("ECM_ApplyFont uses global font settings by default", function()
        local fontString = newFontStringSpy()
        ECM_ApplyFont(fontString, addonNS.Addon.db.profile.global, {
            overrideFont = false,
            font = "Module Font",
            fontSize = 20,
        })

        local call = fontString.setFontCalls[1]
        assert.is_table(call)
        assert.are.equal("FONT:Global Font", call.path)
        assert.are.equal(11, call.size)
        assert.are.equal("OUTLINE", call.outline)

        local shadowOffset = fontString.shadowOffsetCalls[1]
        assert.are.same({ x = 0, y = 0 }, shadowOffset)
        assert.are.equal(0, #fontString.shadowColorCalls)
    end)

    it("ECM_ApplyFont applies module font and size when overrideFont is enabled", function()
        local fontString = newFontStringSpy()
        ECM_ApplyFont(fontString, addonNS.Addon.db.profile.global, {
            overrideFont = true,
            font = "Module Font",
            fontSize = 18,
        })

        local call = fontString.setFontCalls[1]
        assert.are.equal("FONT:Module Font", call.path)
        assert.are.equal(18, call.size)
        assert.are.equal("OUTLINE", call.outline)
    end)

    it("ECM_ApplyFont falls back to global values for missing module fields", function()
        local fontString = newFontStringSpy()
        addonNS.Addon.db.profile.global.fontSize = 13
        ECM_ApplyFont(fontString, addonNS.Addon.db.profile.global, {
            overrideFont = true,
            font = "Module Font",
            fontSize = nil,
        })

        local call = fontString.setFontCalls[1]
        assert.are.equal("FONT:Module Font", call.path)
        assert.are.equal(13, call.size)
    end)

    it("ECM_ApplyFont keeps outline and shadow sourced from global config", function()
        local fontString = newFontStringSpy()
        addonNS.Addon.db.profile.global.fontOutline = "NONE"
        addonNS.Addon.db.profile.global.fontShadow = true

        ECM_ApplyFont(fontString, addonNS.Addon.db.profile.global, {
            overrideFont = true,
            font = "Module Font",
            fontSize = 17,
            fontOutline = "THICKOUTLINE",
            fontShadow = false,
        })

        local call = fontString.setFontCalls[1]
        assert.are.equal("", call.outline)
        assert.are.same({ r = 0, g = 0, b = 0, a = 1 }, fontString.shadowColorCalls[1])
        assert.are.same({ x = 1, y = -1 }, fontString.shadowOffsetCalls[1])
    end)

    it("ECM_ApplyFont falls back to addon global config when globalConfig is omitted", function()
        local fontString = newFontStringSpy()
        addonNS.Addon.db.profile.global.font = "DB Global Font"
        addonNS.Addon.db.profile.global.fontSize = 15

        ECM_ApplyFont(fontString)

        local call = fontString.setFontCalls[1]
        assert.are.equal("FONT:DB Global Font", call.path)
        assert.are.equal(15, call.size)
    end)
end)
