-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

if type(describe) ~= "function" or type(it) ~= "function" then
    return
end

describe("EditModeBridge", function()
    local originalGlobals
    local EditModeBridge
    local LibEQOLStub
    local scheduledTimers

    --- Minimal frame stub
    local function makeFrame(name)
        local frame = {
            __name = name,
            __points = {},
            __shown = true,
            __scripts = {},
        }
        function frame:GetName() return self.__name end
        function frame:SetPoint(point, relativeTo, relativePoint, x, y)
            self.__points[#self.__points + 1] = { point, relativeTo, relativePoint, x, y }
        end
        function frame:ClearAllPoints() self.__points = {} end
        function frame:Show() self.__shown = true end
        function frame:Hide() self.__shown = false end
        function frame:IsShown() return self.__shown end
        function frame:SetAlpha() end
        function frame:GetPoint(index)
            local p = self.__points[index or 1]
            if p then return p[1], p[2], p[3], p[4], p[5] end
        end
        return frame
    end

    --- Minimal module stub that satisfies ModuleMixin's interface
    local function makeModule(name, cfg)
        local module = {
            Name = name,
            InnerFrame = makeFrame("ECM" .. name),
            _configKey = name:sub(1, 1):lower() .. name:sub(2),
            _layoutUpdates = {},
            IsModuleMixin = true,
        }
        function module:GetModuleConfig() return cfg end
        function module:GetGlobalConfig() return { barWidth = 250, barHeight = 22 } end
        function module:ThrottledUpdateLayout(reason)
            self._layoutUpdates[#self._layoutUpdates + 1] = reason
        end
        function module:IsEnabled() return true end
        return module
    end

    setup(function()
        originalGlobals = {}
        for _, name in ipairs({ "ECM", "LibStub", "UIParent", "C_Timer" }) do
            originalGlobals[name] = _G[name]
        end

        scheduledTimers = {}
        _G.C_Timer = { After = function(_, fn) scheduledTimers[#scheduledTimers + 1] = fn end }
        _G.UIParent = makeFrame("UIParent")

        -- Stub LibEQOL
        LibEQOLStub = {
            SettingType = { Slider = 0, Checkbox = 1, Dropdown = 2 },
            _frames = {},
            _settings = {},
            _dragPredicates = {},
        }
        function LibEQOLStub:AddFrame(frame, callback, default)
            self._frames[frame] = { callback = callback, default = default }
        end
        function LibEQOLStub:AddFrameSettings(frame, settings)
            self._settings[frame] = settings
        end
        function LibEQOLStub:SetFrameDragEnabled(frame, predicate)
            self._dragPredicates[frame] = predicate
        end

        _G.LibStub = function(_, name)
            if name == "LibEQOLEditMode-1.0" then return LibEQOLStub end
            return nil
        end
        setmetatable(_G.LibStub, { __call = _G.LibStub })

        _G.ECM = {
            Constants = {
                ADDON_ABRV = "ECM",
                ANCHORMODE_CHAIN = "chain",
                ANCHORMODE_FREE = "free",
                DEFAULT_BAR_WIDTH = 250,
                DEFAULT_FREE_ANCHOR_OFFSET_Y = -300,
            },
        }

        local chunk = loadfile("Modules/EditModeBridge.lua") or loadfile("Modules\\EditModeBridge.lua")
        assert(chunk, "Unable to load EditModeBridge.lua")
        chunk()
        EditModeBridge = ECM.EditModeBridge
    end)

    teardown(function()
        for name, value in pairs(originalGlobals) do
            _G[name] = value
        end
    end)

    describe("Register", function()
        it("registers the InnerFrame with LibEQOL", function()
            local cfg = { anchorMode = "free", offsetX = 10, offsetY = -200, width = 300 }
            local module = makeModule("PowerBar", cfg)

            EditModeBridge.Register(module)

            assert.is_not_nil(LibEQOLStub._frames[module.InnerFrame])
            assert.is_not_nil(LibEQOLStub._settings[module.InnerFrame])
            assert.is_not_nil(LibEQOLStub._dragPredicates[module.InnerFrame])
        end)

        it("passes default position from config", function()
            local cfg = { anchorMode = "free", offsetX = 50, offsetY = -400, freeAnchorPoint = "TOPLEFT" }
            local module = makeModule("ResourceBar", cfg)

            EditModeBridge.Register(module)

            local reg = LibEQOLStub._frames[module.InnerFrame]
            assert.are.equal("TOPLEFT", reg.default.point)
            assert.are.equal(50, reg.default.x)
            assert.are.equal(-400, reg.default.y)
        end)

        it("defaults freeAnchorPoint to CENTER", function()
            local cfg = { anchorMode = "free", offsetX = 0, offsetY = -300 }
            local module = makeModule("RuneBar", cfg)

            EditModeBridge.Register(module)

            local reg = LibEQOLStub._frames[module.InnerFrame]
            assert.are.equal("CENTER", reg.default.point)
        end)

        it("is idempotent — second call is a no-op", function()
            local cfg = { anchorMode = "free" }
            local module = makeModule("PowerBar2", cfg)

            EditModeBridge.Register(module)
            local first = LibEQOLStub._frames[module.InnerFrame]
            EditModeBridge.Register(module)
            local second = LibEQOLStub._frames[module.InnerFrame]

            assert.are.equal(first, second)
        end)

        it("does nothing for modules without InnerFrame", function()
            local module = { Name = "NoFrame", InnerFrame = nil }
            EditModeBridge.Register(module)
            -- No error, no registration
        end)

        it("skips Blizzard frames to avoid taint", function()
            local cfg = { anchorMode = "free" }
            local module = makeModule("BuffBars", cfg)
            -- Simulate BuffBars returning a Blizzard frame (non-ECM name)
            module.InnerFrame = makeFrame("BuffBarCooldownViewer")

            EditModeBridge.Register(module)

            assert.is_nil(LibEQOLStub._frames[module.InnerFrame])
        end)
    end)

    describe("position callback", function()
        it("writes point, x, y to module config on drag", function()
            local cfg = { anchorMode = "free", offsetX = 0, offsetY = -300 }
            local module = makeModule("DragTest", cfg)

            EditModeBridge.Register(module)

            local callback = LibEQOLStub._frames[module.InnerFrame].callback
            callback(module.InnerFrame, "Modern", "TOPLEFT", 100, -200)

            assert.are.equal("TOPLEFT", cfg.freeAnchorPoint)
            assert.are.equal(100, cfg.offsetX)
            assert.are.equal(-200, cfg.offsetY)
        end)

        it("triggers ThrottledUpdateLayout after drag", function()
            local cfg = { anchorMode = "free" }
            local module = makeModule("DragLayout", cfg)

            EditModeBridge.Register(module)

            local callback = LibEQOLStub._frames[module.InnerFrame].callback
            callback(module.InnerFrame, "Modern", "CENTER", 50, -100)

            assert.are.equal(1, #module._layoutUpdates)
            assert.are.equal("EditModeDrag", module._layoutUpdates[1])
        end)

        it("ignores callback when in chain mode", function()
            local cfg = { anchorMode = "chain", offsetX = 0, offsetY = 0 }
            local module = makeModule("ChainIgnore", cfg)

            EditModeBridge.Register(module)

            local callback = LibEQOLStub._frames[module.InnerFrame].callback
            callback(module.InnerFrame, "Modern", "TOPLEFT", 999, -999)

            -- Config should not have been updated
            assert.are.equal(0, cfg.offsetX)
            assert.are.equal(0, cfg.offsetY)
            assert.is_nil(cfg.freeAnchorPoint)
        end)
    end)

    describe("drag predicate", function()
        it("returns true when in free mode", function()
            local cfg = { anchorMode = "free" }
            local module = makeModule("DragFree", cfg)

            EditModeBridge.Register(module)

            local predicate = LibEQOLStub._dragPredicates[module.InnerFrame]
            assert.is_true(predicate())
        end)

        it("returns false when in chain mode", function()
            local cfg = { anchorMode = "chain" }
            local module = makeModule("DragChain", cfg)

            EditModeBridge.Register(module)

            local predicate = LibEQOLStub._dragPredicates[module.InnerFrame]
            assert.is_false(predicate())
        end)

        it("reflects runtime mode changes", function()
            local cfg = { anchorMode = "chain" }
            local module = makeModule("DragSwitch", cfg)

            EditModeBridge.Register(module)

            local predicate = LibEQOLStub._dragPredicates[module.InnerFrame]
            assert.is_false(predicate())

            cfg.anchorMode = "free"
            assert.is_true(predicate())
        end)
    end)

    describe("width setting", function()
        it("provides a slider setting for width", function()
            local cfg = { anchorMode = "free", width = 350 }
            local module = makeModule("WidthTest", cfg)

            EditModeBridge.Register(module)

            local settings = LibEQOLStub._settings[module.InnerFrame]
            assert.are.equal(1, #settings)

            local slider = settings[1]
            assert.are.equal("Width", slider.name)
            assert.are.equal(100, slider.minValue)
            assert.are.equal(600, slider.maxValue)
            assert.are.equal(1, slider.valueStep)
        end)

        it("get returns current width from config", function()
            local cfg = { anchorMode = "free", width = 400 }
            local module = makeModule("WidthGet", cfg)

            EditModeBridge.Register(module)

            local slider = LibEQOLStub._settings[module.InnerFrame][1]
            assert.are.equal(400, slider.get())
        end)

        it("get returns default when width is nil", function()
            local cfg = { anchorMode = "free" }
            local module = makeModule("WidthDefault", cfg)

            EditModeBridge.Register(module)

            local slider = LibEQOLStub._settings[module.InnerFrame][1]
            assert.are.equal(250, slider.get())
        end)

        it("set writes width to config and triggers layout", function()
            local cfg = { anchorMode = "free", width = 300 }
            local module = makeModule("WidthSet", cfg)

            EditModeBridge.Register(module)

            local slider = LibEQOLStub._settings[module.InnerFrame][1]
            slider.set("Modern", 500)

            assert.are.equal(500, cfg.width)
            assert.are.equal(1, #module._layoutUpdates)
            assert.are.equal("EditModeWidth", module._layoutUpdates[1])
        end)
    end)

    describe("UpdateDragState", function()
        it("refreshes the drag predicate via SetFrameDragEnabled", function()
            local cfg = { anchorMode = "free" }
            local module = makeModule("UpdateDrag", cfg)

            EditModeBridge.Register(module)
            local firstPredicate = LibEQOLStub._dragPredicates[module.InnerFrame]

            EditModeBridge.UpdateDragState(module)
            local secondPredicate = LibEQOLStub._dragPredicates[module.InnerFrame]

            -- A new predicate function is installed (same behavior)
            assert.is_function(secondPredicate)
            assert.is_true(secondPredicate())
        end)

        it("does nothing for unregistered modules", function()
            local cfg = { anchorMode = "free" }
            local module = makeModule("Unregistered", cfg)
            -- Not registered — should not error
            EditModeBridge.UpdateDragState(module)
        end)
    end)
end)
