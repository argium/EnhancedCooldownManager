-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ECM layout system", function()
    local originalGlobals
    local fakeTime
    local isMounted
    local inCombat
    local cvarEnabled

    --- Lightweight frame stub for ECM integration tests (no call tracking needed)
    local function makeFrame(opts)
        opts = opts or {}
        local frame = {
            __shown = opts.shown ~= false,
            __alpha = opts.alpha or 1,
            __height = opts.height or 0,
            __width = opts.width or 0,
            __anchors = {},
        }

        function frame:Show() self.__shown = true end
        function frame:Hide() self.__shown = false end
        function frame:IsShown() return self.__shown end
        function frame:SetAlpha(a) self.__alpha = a end
        function frame:GetAlpha() return self.__alpha end
        function frame:SetHeight(h) self.__height = h end
        function frame:GetHeight() return self.__height end
        function frame:SetWidth(w) self.__width = w end
        function frame:GetWidth() return self.__width end
        function frame:SetPoint() end
        function frame:GetPoint() end
        function frame:GetNumPoints() return #self.__anchors end
        function frame:ClearAllPoints() self.__anchors = {} end
        function frame:GetName() return opts.name end
        function frame:SetScript() end
        function frame:RegisterEvent() end
        function frame:HookScript() end
        function frame:GetEffectiveScale() return 1 end
        function frame:GetBackdropBorderColor() return 0, 0, 0, 1 end
        function frame:GetBackdrop() return nil end
        function frame:GetColorTexture() return nil end
        function frame:SetColorTexture() end
        function frame:GetVertexColor() return nil end
        function frame:IsObjectType() return false end

        return frame
    end

    local function makeModule(name)
        local innerFrame = makeFrame({ name = "ECM" .. name, shown = true })
        innerFrame.Background = makeFrame()
        innerFrame.Border = makeFrame({ shown = false })

        local mod = {
            Name = name,
            InnerFrame = innerFrame,
            IsHidden = false,
            _lastUpdate = 0,
            _configKey = name:sub(1, 1):lower() .. name:sub(2),
        }

        function mod:SetHidden(hide) self.IsHidden = hide end
        function mod:ShouldShow() return not self.IsHidden end
        function mod:IsEnabled() return true end
        function mod:GetGlobalConfig() local p = _G._testDB and _G._testDB.profile; return p and p.global end
        function mod:GetModuleConfig() local p = _G._testDB and _G._testDB.profile; return p and p[self._configKey] end
        function mod:CalculateLayoutParams()
            local gc = self:GetGlobalConfig()
            local mc = self:GetModuleConfig()
            return {
                mode = mc.anchorMode,
                anchor = _G.UIParent,
                isFirst = true,
                anchorPoint = "TOPLEFT",
                anchorRelativePoint = "BOTTOMLEFT",
                offsetX = 0,
                offsetY = -((gc and gc.offsetY) or 0),
                height = (mc and mc.height) or (gc and gc.barHeight),
                width = mc.anchorMode == ECM.Constants.ANCHORMODE_FREE and ((mc and mc.width) or (gc and gc.barWidth)) or nil,
            }
        end
        function mod:GetNextChainAnchor() return _G.UIParent, true end
        function mod:UpdateLayout(why)
            if not self:ShouldShow() then self.InnerFrame:Hide(); return false end
            if not self.InnerFrame:IsShown() then self.InnerFrame:Show() end
            local params = self:CalculateLayoutParams()
            if params.height then ECM.FrameUtil.LazySetHeight(self.InnerFrame, params.height) end
            if params.width then ECM.FrameUtil.LazySetWidth(self.InnerFrame, params.width) end
            self:ThrottledRefresh("UpdateLayout(" .. (why or "") .. ")")
            return true
        end
        function mod:Refresh() return true end
        function mod:ThrottledRefresh(why)
            local gc = self:GetGlobalConfig()
            local freq = (gc and gc.updateFrequency) or ECM.Constants.DEFAULT_REFRESH_FREQUENCY
            if GetTime() - (self._lastUpdate or 0) < freq then return false end
            self:Refresh(why)
            self._lastUpdate = GetTime()
            return true
        end
        function mod:ThrottledUpdateLayout(reason) if self:IsEnabled() then self:UpdateLayout(reason) end end

        return mod
    end

    local function makeRegisteredModule(name)
        local mod = makeModule(name or "PowerBar")
        ECM.RegisterFrame(mod)
        return mod
    end

    local function makeFadeConfig(opacity)
        return {
            enabled = true,
            opacity = opacity,
            exceptIfTargetCanBeAttacked = false,
            exceptIfTargetCanBeHelped = false,
            exceptInInstance = false,
        }
    end

    local CAPTURED_GLOBALS = {
        "ECM", "ColorUtil", "LibStub", "C_Timer", "C_CVar", "GetTime",
        "UIParent", "CreateFrame", "IsMounted", "UnitInVehicle", "IsResting",
        "InCombatLockdown", "UnitExists", "UnitIsDead", "UnitCanAttack",
        "UnitCanAssist", "IsInInstance", "issecretvalue", "issecrettable",
        "Enum", "print", "StaticPopupDialogs", "StaticPopup_Show",
        "YES", "NO", "DevTool", "tinsert", "strtrim", "ReloadUI",
        "AddonCompartmentFrame", "CLOSE", "CANCEL", "OKAY",
        "CooldownViewerSettings",
    }

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(CAPTURED_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        fakeTime = 100
        isMounted = false
        inCombat = false
        cvarEnabled = true

        _G.GetTime = function() return fakeTime end
        _G.IsMounted = function() return isMounted end
        _G.UnitInVehicle = function() return false end
        _G.IsResting = function() return false end
        _G.InCombatLockdown = function() return inCombat end
        _G.UnitExists = function() return false end
        _G.UnitIsDead = function() return false end
        _G.UnitCanAttack = function() return false end
        _G.UnitCanAssist = function() return false end
        _G.IsInInstance = function() return false end
        _G.issecretvalue = function() return false end
        _G.issecrettable = function() return false end
        _G.tinsert = table.insert
        _G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
        _G.print = function() end
        _G.StaticPopupDialogs = {}
        _G.StaticPopup_Show = function() end
        _G.YES = "Yes"
        _G.NO = "No"
        _G.DevTool = nil
        _G.ReloadUI = function() end
        _G.AddonCompartmentFrame = nil
        _G.CLOSE = "Close"
        _G.CANCEL = "Cancel"
        _G.OKAY = "Okay"
        _G.CooldownViewerSettings = nil

        _G.C_CVar = {
            GetCVarBool = function(name) return name == "cooldownViewerEnabled" and cvarEnabled end,
            SetCVar = function() end,
        }
        _G.C_Timer = { After = function(_, callback) callback() end, NewTicker = function() end }
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.CreateFrame = function() return makeFrame() end
        _G.ColorUtil = {
            Sparkle = function(text) return text end,
            AreEqual = function(a, b)
                if a == nil and b == nil then return true end
                if a == nil or b == nil then return false end
                return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
            end,
        }

        local fakeAddon = { RegisterChatCommand = function() end, RegisterEvent = function() end, UnregisterEvent = function() end }
        _G.LibStub = setmetatable({}, {
            __call = function(_, name, silent)
                if name == "AceAddon-3.0" then return { NewAddon = function(_, n) fakeAddon.name = n; return fakeAddon end } end
                if silent then return nil end
                return {}
            end,
        })

        TestHelpers.LoadChunk("Tests/stubs/Enums.lua", "Unable to load Enums.lua")()
        _G.ECM = {}
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("ECM_Defaults.lua", "Unable to load ECM_Defaults.lua")()
        _G.ECM.Migration = { PrepareDatabase = function() end, Run = function() end, FlushLog = function() end, PrintLog = function() end }
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()
        TestHelpers.LoadChunk("Helpers/ModuleMixin.lua", "Unable to load Helpers/ModuleMixin.lua")(nil, { Addon = fakeAddon })
        TestHelpers.LoadChunk("Helpers/FrameMixin.lua", "Unable to load Helpers/FrameMixin.lua")(nil, { Addon = fakeAddon })

        local profile = TestHelpers.deepClone(ECM.defaults.profile)
        _G._testDB = { profile = profile }
        fakeAddon.db = _G._testDB

        TestHelpers.LoadChunk("ECM.lua", "Unable to load ECM.lua")("EnhancedCooldownManager", { Addon = fakeAddon })
    end)

    describe("automatic layout enforcement", function()
        it("hides registered module frames when mounted", function()
            local mod = makeRegisteredModule()
            isMounted = true

            ECM.ScheduleLayoutUpdate(0, "mount")

            assert.is_true(mod.IsHidden)
            assert.is_false(mod.InnerFrame:IsShown())
        end)

        it("applies fade alpha when out of combat", function()
            local mod = makeRegisteredModule()
            _G._testDB.profile.global.outOfCombatFade = makeFadeConfig(50)

            ECM.ScheduleLayoutUpdate(0, "fade")

            assert.are.equal(0.5, mod.InnerFrame:GetAlpha())
        end)

        it("re-shows module frames after dismounting", function()
            local mod = makeRegisteredModule()

            isMounted = true
            ECM.ScheduleLayoutUpdate(0, "mount")
            assert.is_false(mod.InnerFrame:IsShown())

            fakeTime = fakeTime + 1
            isMounted = false
            ECM.ScheduleLayoutUpdate(0, "dismount")
            assert.is_true(mod.InnerFrame:IsShown())
        end)

        it("restores full alpha when combat fade is disabled", function()
            local mod = makeRegisteredModule()
            _G._testDB.profile.global.outOfCombatFade = makeFadeConfig(30)
            ECM.ScheduleLayoutUpdate(0, "fade-on")
            assert.are.equal(0.3, mod.InnerFrame:GetAlpha())

            fakeTime = fakeTime + 1
            _G._testDB.profile.global.outOfCombatFade.enabled = false
            ECM.ScheduleLayoutUpdate(0, "fade-off")
            assert.are.equal(1, mod.InnerFrame:GetAlpha())
        end)

        it("hides all registered modules when cvar is disabled", function()
            local mod1 = makeRegisteredModule("PowerBar")
            local mod2 = makeRegisteredModule("ResourceBar")

            cvarEnabled = false
            ECM.ScheduleLayoutUpdate(0, "cvar-off")

            assert.is_true(mod1.IsHidden)
            assert.is_true(mod2.IsHidden)
        end)

        it("re-hides a module frame that was externally shown while hidden", function()
            local mod = makeRegisteredModule()
            isMounted = true
            ECM.ScheduleLayoutUpdate(0, "mount")

            mod.InnerFrame:Show()

            fakeTime = fakeTime + 1
            ECM.ScheduleLayoutUpdate(0, "re-enforce")
            assert.is_false(mod.InnerFrame:IsShown())
        end)
    end)
end)
