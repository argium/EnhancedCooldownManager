-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ColorUtil", function()
    local originalGlobals
    local ColorUtil
    local ns

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({})
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        ns = {}

        TestHelpers.LoadChunk("Helpers/ColorUtil.lua", "Unable to load Helpers/ColorUtil.lua")(nil, ns)
        ColorUtil = assert(ns.ColorUtil, "ColorUtil did not initialize")
    end)

    it("AreEqual handles identical, nil, and distinct colors", function()
        local color = { r = 1, g = 0.5, b = 0.25, a = 1 }

        assert.is_true(ColorUtil.AreEqual(color, color))
        assert.is_true(ColorUtil.AreEqual(nil, nil))
        assert.is_false(ColorUtil.AreEqual(color, nil))
        assert.is_false(ColorUtil.AreEqual(color, { r = 1, g = 0.5, b = 0.25, a = 0.5 }))
    end)

    it("ColorToHex converts normalized RGB values to lowercase hex", function()
        local hex = ColorUtil.ColorToHex({ r = 1, g = 0.5, b = 0, a = 1 })
        assert.are.equal("ff8000", hex)
    end)

    it("Sparkle supports empty input and hex color strings", function()
        assert.are.equal("", ColorUtil.Sparkle(""))

        local result = ColorUtil.Sparkle("AB", "80112233", "80112233", "80112233")
        assert.are.equal("|cff112233A|r|cff112233B|r", result)
    end)

    it("Sparkle accepts 0..255 array colors", function()
        local result = ColorUtil.Sparkle("AB", { 255, 128, 0 }, { 255, 128, 0 }, { 255, 128, 0 })
        assert.are.equal("|cffff8000A|r|cffff8000B|r", result)
    end)

    it("Sparkle clamps out-of-range table values", function()
        local result = ColorUtil.Sparkle("AB", { -1, 2, 0.5 }, { -1, 2, 0.5 }, { -1, 2, 0.5 })
        assert.are.equal("|cff000201A|r|cff000201B|r", result)
    end)

    it("Sparkle rejects unsupported color types", function()
        assert.has_error(function()
            ColorUtil.Sparkle("A", 42, "ffffff", "ffffff")
        end)
    end)
end)
