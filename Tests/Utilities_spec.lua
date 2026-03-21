-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

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
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "LibStub",
            "SlashCmdList",
            "hash_SlashCmdList",
            "CreateFrame",
            "issecretvalue",
            "issecrettable",
            "InCombatLockdown",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.ECM = {
            defaults = {},
            Migration = {},
        }
        addonNS = {
            Addon = {
                SetDefaultModuleLibraries = function() end,
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

        TestHelpers.SetupLibStub()
        _G.SlashCmdList = {}
        _G.hash_SlashCmdList = {}
        local aceAddon = _G.LibStub:NewLibrary("AceAddon-3.0", 1)
        aceAddon.NewAddon = function()
            return addonNS.Addon
        end
        local sharedMedia = _G.LibStub:NewLibrary("LibSharedMedia-3.0", 1)
        sharedMedia.Fetch = function(_, mediaType, key)
            if mediaType == "font" and type(key) == "string" then
                return "FONT:" .. key
            end
            return nil
        end
        TestHelpers.SetupLibEQOLEditModeStub()
        _G.ECM.ColorUtil = {
            Sparkle = function(text)
                return text
            end,
        }
        _G.ECM.DebugAssert = function() end
        _G.ECM.Runtime = { ScheduleLayoutUpdate = function() end }
        _G.CreateFrame = function()
            return {
                SetScript = function() end,
                RegisterEvent = function() end,
                UnregisterEvent = function() end,
            }
        end
        _G.issecretvalue = function() return false end
        _G.issecrettable = function() return false end
        _G.InCombatLockdown = function() return false end

        TestHelpers.LoadChunk("Libs/LibConsole/LibConsole.lua", "Unable to load LibConsole.lua")()
        TestHelpers.LoadChunk("Libs/LibEvent/LibEvent.lua", "Unable to load LibEvent.lua")()
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")()
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()
        TestHelpers.LoadChunk("Helpers/ModuleMixin.lua", "Unable to load Helpers/ModuleMixin.lua")(nil, addonNS)
        TestHelpers.LoadChunk("Helpers/FrameMixin.lua", "Unable to load Helpers/FrameMixin.lua")(nil, addonNS)
        TestHelpers.LoadChunk("ECM.lua", "Unable to load ECM.lua")("EnhancedCooldownManager", addonNS)
    end)

    it("ECM.ApplyFont uses global font settings by default", function()
        local fontString = newFontStringSpy()
        ECM.ApplyFont(fontString, addonNS.Addon.db.profile.global, {
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

    it("ECM.ApplyFont applies module font and size when overrideFont is enabled", function()
        local fontString = newFontStringSpy()
        ECM.ApplyFont(fontString, addonNS.Addon.db.profile.global, {
            overrideFont = true,
            font = "Module Font",
            fontSize = 18,
        })

        local call = fontString.setFontCalls[1]
        assert.are.equal("FONT:Module Font", call.path)
        assert.are.equal(18, call.size)
        assert.are.equal("OUTLINE", call.outline)
    end)

    it("ECM.ApplyFont falls back to global values for missing module fields", function()
        local fontString = newFontStringSpy()
        addonNS.Addon.db.profile.global.fontSize = 13
        ECM.ApplyFont(fontString, addonNS.Addon.db.profile.global, {
            overrideFont = true,
            font = "Module Font",
            fontSize = nil,
        })

        local call = fontString.setFontCalls[1]
        assert.are.equal("FONT:Module Font", call.path)
        assert.are.equal(13, call.size)
    end)

    it("ECM.ApplyFont keeps outline and shadow sourced from global config", function()
        local fontString = newFontStringSpy()
        addonNS.Addon.db.profile.global.fontOutline = "NONE"
        addonNS.Addon.db.profile.global.fontShadow = true

        ECM.ApplyFont(fontString, addonNS.Addon.db.profile.global, {
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

    it("ECM.ApplyFont falls back to addon global config when globalConfig is omitted", function()
        local fontString = newFontStringSpy()
        addonNS.Addon.db.profile.global.font = "DB Global Font"
        addonNS.Addon.db.profile.global.fontSize = 15

        ECM.ApplyFont(fontString)

        local call = fontString.setFontCalls[1]
        assert.are.equal("FONT:DB Global Font", call.path)
        assert.are.equal(15, call.size)
    end)
end)
