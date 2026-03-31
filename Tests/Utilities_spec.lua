-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("Utilities", function()
    local originalGlobals
    local ns

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
        ns = {
            defaults = {},
            Migration = {},
        }
        ns.Addon = {
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
        }

        TestHelpers.SetupLibStub()
        _G.SlashCmdList = {}
        _G.hash_SlashCmdList = {}
        local aceAddon = _G.LibStub:NewLibrary("AceAddon-3.0", 1)
        aceAddon.NewAddon = function()
            return ns.Addon
        end
        local sharedMedia = _G.LibStub:NewLibrary("LibSharedMedia-3.0", 1)
        sharedMedia.Fetch = function(_, mediaType, key)
            if mediaType == "font" and type(key) == "string" then
                return "FONT:" .. key
            end
            return nil
        end
        TestHelpers.SetupLibEditModeStub()
        ns.ColorUtil = {
            Sparkle = function(text)
                return text
            end,
        }
        ns.DebugAssert = function() end
        ns.Runtime = { ScheduleLayoutUpdate = function() end }
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
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)
        TestHelpers.LoadChunk("FrameUtil.lua", "Unable to load FrameUtil.lua")(nil, ns)
        TestHelpers.LoadChunk("BarMixin.lua", "Unable to load BarMixin.lua")(nil, ns)
        TestHelpers.LoadChunk("ECM.lua", "Unable to load ECM.lua")("EnhancedCooldownManager", ns)
    end)

    it("ECM.ApplyFont uses global font settings by default", function()
        local fontString = newFontStringSpy()
        ns.FrameUtil.ApplyFont(fontString, ns.Addon.db.profile.global, {
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
        ns.FrameUtil.ApplyFont(fontString, ns.Addon.db.profile.global, {
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
        ns.Addon.db.profile.global.fontSize = 13
        ns.FrameUtil.ApplyFont(fontString, ns.Addon.db.profile.global, {
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
        ns.Addon.db.profile.global.fontOutline = "NONE"
        ns.Addon.db.profile.global.fontShadow = true

        ns.FrameUtil.ApplyFont(fontString, ns.Addon.db.profile.global, {
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
        ns.Addon.db.profile.global.font = "DB Global Font"
        ns.Addon.db.profile.global.fontSize = 15

        ns.FrameUtil.ApplyFont(fontString)

        local call = fontString.setFontCalls[1]
        assert.are.equal("FONT:DB Global Font", call.path)
        assert.are.equal(15, call.size)
    end)
end)
