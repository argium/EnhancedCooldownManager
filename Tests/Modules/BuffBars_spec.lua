-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("BuffBars module", function()
    local originalGlobals
    local BuffBars

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({ "issecretvalue" })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.issecretvalue = function() return false end
        BuffBars = {}

        -- Replicate FormatNameWithApplications from Modules/BuffBars.lua
        function BuffBars.FormatNameWithApplications(nameText, appText)
            if not appText then return nil end
            local hasApps = issecretvalue(appText)
            if not hasApps then
                local count = tonumber(appText)
                hasApps = count and count > 1
            end
            if not hasApps then return nil end
            if not issecretvalue(nameText) then
                if not nameText then return nil end
            end
            return nameText .. " (" .. appText .. ")"
        end
    end)

    describe("FormatNameWithApplications", function()
        it("returns nil when appText is nil", function()
            assert.is_nil(BuffBars.FormatNameWithApplications("Renew", nil))
        end)

        it("returns nil when appText is empty string", function()
            assert.is_nil(BuffBars.FormatNameWithApplications("Renew", ""))
        end)

        it("returns nil when application count is 1", function()
            assert.is_nil(BuffBars.FormatNameWithApplications("Renew", "1"))
        end)

        it("returns nil when application count is 0", function()
            assert.is_nil(BuffBars.FormatNameWithApplications("Renew", "0"))
        end)

        it("appends count when applications > 1", function()
            assert.are.equal("Renew (3)", BuffBars.FormatNameWithApplications("Renew", "3"))
        end)

        it("handles large application counts", function()
            assert.are.equal("Shield (25)", BuffBars.FormatNameWithApplications("Shield", "25"))
        end)

        it("returns nil when nameText is nil and appText is valid", function()
            assert.is_nil(BuffBars.FormatNameWithApplications(nil, "3"))
        end)

        it("handles secret appText by always appending", function()
            _G.issecretvalue = function(v) return v == "SECRET_APP" end
            assert.are.equal("Renew (SECRET_APP)",
                BuffBars.FormatNameWithApplications("Renew", "SECRET_APP"))
        end)

        it("handles secret nameText with valid appText", function()
            _G.issecretvalue = function(v) return v == "SECRET_NAME" end
            assert.are.equal("SECRET_NAME (3)",
                BuffBars.FormatNameWithApplications("SECRET_NAME", "3"))
        end)

        it("handles both secret nameText and appText", function()
            _G.issecretvalue = function() return true end
            assert.are.equal("SECRET_NAME (SECRET_APP)",
                BuffBars.FormatNameWithApplications("SECRET_NAME", "SECRET_APP"))
        end)
    end)
end)
