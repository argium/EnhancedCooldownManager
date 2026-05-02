-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("About section", function()
    local originalGlobals
    local SB, ns, root

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()
        local profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        _G.C_AddOns = {
            GetAddOnMetadata = function(_, key)
                if key == "Version" then
                    return "v1.2.3-test"
                end
            end,
        }

        ns.ColorUtil = {
            Sparkle = function(text)
                return "<<sparkle:" .. text .. ">>"
            end,
        }
    end)

    local function findInitializer(layout, predicate)
        for _, init in ipairs(layout._initializers) do
            if predicate(init) then
                return init
            end
        end
    end

    local function getInitializerData(init)
        return init and (init._lsbData or (init.GetData and init:GetData()) or init.data) or nil
    end

    local function findInfoRow(layout, name)
        return findInitializer(layout, function(init)
            local data = getInitializerData(init)
            return data and data._lsbKind == "infoRow" and data.name == name
        end)
    end

    it("exports an About root page spec", function()
        assert.is_table(ns.AboutPage)
        assert.are.equal("about", ns.AboutPage.key)
    end)

    describe("root registration", function()
        local rootLayout

        before_each(function()
            root = TestHelpers.RegisterRootPageSpec(SB, ns.AboutPage, ns.L["ADDON_NAME"])
            rootLayout = root._category:GetLayout()
        end)

        it("adds initializers to the root category layout", function()
            assert.is_true(#rootLayout._initializers > 0)
        end)

        it("creates Author info row with sparkle text", function()
            local init = findInfoRow(rootLayout, "Author")
            assert.is_not_nil(init, "expected Author info row")
            local data = getInitializerData(init)
            assert.are.equal("<<sparkle:Argi>>", type(data.value) == "function" and data.value() or data.value)
        end)

        it("creates Contributors info row", function()
            local init = findInfoRow(rootLayout, "Contributors")
            assert.is_not_nil(init, "expected Contributors info row")
            local data = getInitializerData(init)
            assert.are.equal("kayti-wow", type(data.value) == "function" and data.value() or data.value)
        end)

        it("creates Version info row with leading v stripped", function()
            local init = findInfoRow(rootLayout, "Version")
            assert.is_not_nil(init, "expected Version info row")
            local data = getInitializerData(init)
            assert.are.equal("1.2.3-test", type(data.value) == "function" and data.value() or data.value)
        end)

        it("includes Links subheader", function()
            local init = findInitializer(rootLayout, function(i)
                local data = getInitializerData(i)
                return data and data._lsbKind == "subheader" and data.name == "Links"
            end)
            assert.is_not_nil(init, "expected Links subheader")
        end)

        it("adds plain button rows for the links", function()
            local curseforge = TestHelpers.FindButtonInitializer(rootLayout._initializers, ns.L["CURSEFORGE"])
            local github = TestHelpers.FindButtonInitializer(rootLayout._initializers, ns.L["GITHUB"])

            assert.is_not_nil(curseforge, "expected CurseForge button row")
            assert.is_not_nil(github, "expected GitHub button row")
        end)

        it("CurseForge button calls ShowCopyTextDialog with correct URL", function()
            local captured
            ns.Addon.ShowCopyTextDialog = function(_, url, title)
                captured = { url = url, title = title }
            end

            TestHelpers.FindButtonInitializer(rootLayout._initializers, ns.L["CURSEFORGE"])._onClick()

            assert.is_not_nil(captured)
            assert.are.equal("https://www.curseforge.com/wow/addons/enhanced-cooldown-manager", captured.url)
            assert.are.equal("CurseForge", captured.title)
        end)

        it("GitHub button calls ShowCopyTextDialog with correct URL", function()
            local captured
            ns.Addon.ShowCopyTextDialog = function(_, url, title)
                captured = { url = url, title = title }
            end

            TestHelpers.FindButtonInitializer(rootLayout._initializers, ns.L["GITHUB"])._onClick()

            assert.is_not_nil(captured)
            assert.are.equal("https://github.com/argium/EnhancedCooldownManager", captured.url)
            assert.are.equal("GitHub", captured.title)
        end)

        it("does not create a subcategory for About", function()
            assert.is_nil(SB._subcategories["About"])
            assert.is_nil(SB._subcategories["Enhanced Cooldown Manager"])
        end)
    end)

    describe("version fallback", function()
        it("uses 'Unknown' when GetAddOnMetadata returns nil", function()
            _G.C_AddOns = {
                GetAddOnMetadata = function()
                    return nil
                end,
            }

            local profile, defaults = TestHelpers.MakeOptionsProfile()
            local freshSB, freshNS = TestHelpers.SetupOptionsEnv(profile, defaults)
            freshNS.ColorUtil = ns.ColorUtil
            local freshRoot = TestHelpers.RegisterRootPageSpec(freshSB, freshNS.AboutPage, freshNS.L["ADDON_NAME"])
            local freshRootLayout = freshRoot._category:GetLayout()

            local init = findInfoRow(freshRootLayout, "Version")
            assert.is_not_nil(init, "expected Version info row")
            local data = getInitializerData(init)
            assert.are.equal("Unknown", type(data.value) == "function" and data.value() or data.value)
        end)
    end)
end)
