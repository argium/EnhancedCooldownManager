-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ECM = ns.Addon
local C = ns.Constants
local Util = ns.Util
local SecretedStore = ns.SecretedStore

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local LAYOUT_EVENTS = {
    PLAYER_MOUNT_DISPLAY_CHANGED = { delay = 0 },
    UNIT_ENTERED_VEHICLE = { delay = 0 },
    UNIT_EXITED_VEHICLE = { delay = 0 },
    VEHICLE_UPDATE = { delay = 0 },
    PLAYER_UPDATE_RESTING = { delay = 0 },
    PLAYER_SPECIALIZATION_CHANGED = { delay = 0 },
    PLAYER_ENTERING_WORLD = { delay = 0.4 },
    PLAYER_TARGET_CHANGED = { delay = 0 },
    PLAYER_REGEN_ENABLED = { delay = 0.1, combatChange = true },
    PLAYER_REGEN_DISABLED = { delay = 0, combatChange = true },
    ZONE_CHANGED_NEW_AREA = { delay = 0.1 },
    ZONE_CHANGED = { delay = 0.1 },
    ZONE_CHANGED_INDOORS = { delay = 0.1 },
    UPDATE_SHAPESHIFT_FORM = { delay = 0 },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local _ecmFrames = {}
local _globallyHidden = false
local _hideReason = nil
local _inCombat = InCombatLockdown()
local _layoutPending = false
local _lastAlpha = 1
local _scanners = {}
local _scannerOrder = {}
local _runningScanners = false

local ScheduleLayoutUpdate

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Iterates over all Blizzard cooldown viewer frames.
--- @param fn fun(frame: Frame, name: string)
local function ForEachBlizzardFrame(fn)
    for _, name in ipairs(C.BLIZZARD_FRAMES) do
        local frame = _G[name]
        if frame then
            fn(frame, name)
        end
    end
end

--- Sets the globally hidden state for all frames (ECMFrames + Blizzard frames).
--- @param hidden boolean Whether to hide all frames
--- @param reason string|nil Reason for hiding ("mounted", "rest", "cvar")
local function SetGloballyHidden(hidden, reason)
    if _globallyHidden == hidden and _hideReason == reason then
        return
    end

    Util.Log("Layout", "SetGloballyHidden", { hidden = hidden, reason = reason })

    _globallyHidden = hidden
    _hideReason = reason

    -- Hide/show Blizzard frames
    ForEachBlizzardFrame(function(frame)
        if hidden then
            if frame:IsShown() then
                frame:Hide()
            end
        else
            frame:Show()
        end
    end)

    -- Hide/show ECMFrames
    for _, ecmFrame in pairs(_ecmFrames) do
        ecmFrame:SetHidden(hidden)
    end
end

local function SetAlpha(alpha)
    if _lastAlpha == alpha then
        return
    end

    ForEachBlizzardFrame(function(frame)
        frame:SetAlpha(alpha)
    end)

    for _, ecmFrame in pairs(_ecmFrames) do
        ecmFrame.InnerFrame:SetAlpha(alpha)
    end

    _lastAlpha = alpha
end

--- Checks all fade and hide conditions and updates global state.
local function UpdateFadeAndHiddenStates()
    local globalConfig = ECM.db and ECM.db.profile and ECM.db.profile.global
    if not globalConfig then
        return
    end

    -- Check CVar first
    if not C_CVar.GetCVarBool("cooldownViewerEnabled") then
        SetGloballyHidden(true, "cvar")
        return
    end

    -- Check mounted or in vehicle
    if globalConfig.hideWhenMounted and (IsMounted() or UnitInVehicle("player")) then
        SetGloballyHidden(true, "mounted")
        return
    end

    if not _inCombat and globalConfig.hideOutOfCombatInRestAreas and IsResting() then
        SetGloballyHidden(true, "rest")
        return
    end

    -- No hide reason, show everything
    SetGloballyHidden(false, nil)

    local alpha = 1
    local fadeConfig = globalConfig.outOfCombatFade
    if not _inCombat and fadeConfig and fadeConfig.enabled then
        local shouldSkipFade = false

        if fadeConfig.exceptInInstance then
            local inInstance, instanceType = IsInInstance()
            if inInstance and C.GROUP_INSTANCE_TYPES[instanceType] then
                shouldSkipFade = true
            end
        end

        if not shouldSkipFade and fadeConfig.exceptIfTargetCanBeAttacked and UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target") then
            shouldSkipFade = true
        end

        if not shouldSkipFade then
            local opacity = fadeConfig.opacity or 100
            alpha = math.max(0, math.min(1, opacity / 100))
        end
    end

    SetAlpha(alpha)
end

--- Calls UpdateLayout on all registered ECMFrames.
local function UpdateAllLayouts()
    local updated = {}

    -- Chain frames must update in deterministic order so downstream bars can
    -- resolve anchors against already-laid-out predecessors.
    for _, moduleName in ipairs(C.CHAIN_ORDER) do
        local ecmFrame = _ecmFrames[moduleName]
        if ecmFrame then
            ecmFrame:UpdateLayout()
            updated[moduleName] = true
        end
    end

    -- Update all remaining frames (non-chain modules).
    for frameName, ecmFrame in pairs(_ecmFrames) do
        if not updated[frameName] then
            ecmFrame:UpdateLayout()
        end
    end
end

--- Returns current class ID and spec ID, or nil, nil if either is unavailable.
---@return number|nil classID, number|nil specID
local function GetCurrentClassSpec()
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()
    if not classID or not specID then
        return nil, nil
    end

    return classID, specID
end

--- Ensures buff-bar discovery storage exists in profile.
---@return table|nil colors
local function EnsureBuffBarStorage()
    local colors = SecretedStore and SecretedStore.GetPath and SecretedStore.GetPath({ "buffBars", "colors" }, true) or nil
    if type(colors) ~= "table" then
        return nil
    end

    if type(colors.cache) ~= "table" then
        colors.cache = {}
    end
    if type(colors.textureMap) ~= "table" then
        colors.textureMap = {}
    end

    return colors
end

---@return table|nil colors, number|nil classID, number|nil specID
local function GetBuffBarDiscoveryContext()
    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return nil, nil, nil
    end

    local colors = EnsureBuffBarStorage()
    if not colors then
        return nil, nil, nil
    end

    colors.cache[classID] = colors.cache[classID] or {}
    colors.textureMap[classID] = colors.textureMap[classID] or {}

    return colors, classID, specID
end

---@param oldEntry table|nil
---@param newEntry table|nil
---@return boolean equivalent
local function AreDiscoveryEntriesEquivalent(oldEntry, newEntry)
    local oldName = type(oldEntry) == "table" and oldEntry.spellName or nil
    local newName = type(newEntry) == "table" and newEntry.spellName or nil
    return oldName == newName
end

---@param scanEntries table[]
---@return table<number, table>, table<number, number|nil>
local function BuildBuffBarDiscoveryMaps(scanEntries)
    local nextCache = {}
    local nextTextureMap = {}
    local now = GetTime()

    local specs = {
        spellName = { valueType = "string", trim = true, emptyToNil = true },
        textureFileID = { valueType = "number" },
    }

    for index, entry in ipairs(scanEntries) do
        local normalized = SecretedStore and SecretedStore.NormalizeRecord and SecretedStore.NormalizeRecord(entry, specs) or {}
        nextCache[index] = {
            spellName = normalized.spellName,
            lastSeen = now,
        }
        nextTextureMap[index] = normalized.textureFileID
    end

    return nextCache, nextTextureMap
end

--- Registers or replaces a scanner callback run during layout passes.
---@param name string
---@param scannerFn fun(reason: string|nil): boolean
---@param opts table|nil
local function RegisterScanner(name, scannerFn, opts)
    assert(type(name) == "string" and name ~= "", "RegisterScanner: name required")
    assert(type(scannerFn) == "function", "RegisterScanner: scannerFn must be a function")

    if not _scanners[name] then
        _scannerOrder[#_scannerOrder + 1] = name
    end

    _scanners[name] = {
        fn = scannerFn,
        opts = opts or {},
    }
end

---@param name string
local function UnregisterScanner(name)
    if type(name) ~= "string" or not _scanners[name] then
        return
    end

    _scanners[name] = nil

    for i, scannerName in ipairs(_scannerOrder) do
        if scannerName == name then
            table.remove(_scannerOrder, i)
            break
        end
    end
end

---@param reason string|nil
---@return boolean changed
local function RunScanners(reason)
    if _runningScanners then
        return false
    end

    _runningScanners = true

    local changed = false
    for _, scannerName in ipairs(_scannerOrder) do
        local scanner = _scanners[scannerName]
        if scanner and type(scanner.fn) == "function" then
            local ok, didChange = pcall(scanner.fn, reason)
            if not ok then
                Util.Log("Layout", "Scanner failed", {
                    scanner = scannerName,
                    reason = reason,
                })
            elseif didChange then
                changed = true
            end
        end
    end

    _runningScanners = false
    return changed
end

--- Refreshes buff-bar discovery cache from current viewer children.
---@param reason string|nil
---@return boolean changed
local function RefreshBuffBarDiscovery(reason)
    local colors, classID, specID = GetBuffBarDiscoveryContext()
    if not colors or not classID or not specID then
        return false
    end

    local buffBars = ECM.BuffBars or ECM:GetModule(C.BUFFBARS, true)
    if not buffBars or (buffBars.IsEnabled and not buffBars:IsEnabled()) or type(buffBars.CollectScanEntries) ~= "function" then
        return false
    end

    local scanEntries = buffBars:CollectScanEntries()
    if type(scanEntries) ~= "table" or #scanEntries == 0 then
        return false
    end

    local oldCache = colors.cache[classID][specID]
    local oldTextureMap = colors.textureMap[classID][specID]

    local nextCache, nextTextureMap = BuildBuffBarDiscoveryMaps(scanEntries)

    local buffBarColors = ns.BuffBarColors
    local didResolveOrMigrate = false
    if buffBarColors and type(buffBarColors.ResolveDiscoveryColors) == "function" then
        didResolveOrMigrate = buffBarColors.ResolveDiscoveryColors(
            classID,
            specID,
            oldCache,
            oldTextureMap,
            nextCache,
            nextTextureMap
        ) or false
    end

    local changed = SecretedStore and SecretedStore.HasIndexedMapsChanged and SecretedStore.HasIndexedMapsChanged(
        oldCache,
        nextCache,
        oldTextureMap,
        nextTextureMap,
        AreDiscoveryEntriesEquivalent
    ) or true

    colors.cache[classID][specID] = nextCache
    colors.textureMap[classID][specID] = nextTextureMap

    if changed or didResolveOrMigrate then
        Util.Log("Layout", "RefreshBuffBarDiscovery", {
            reason = reason,
            changed = changed,
            didResolveOrMigrate = didResolveOrMigrate,
        })
    end

    return changed or didResolveOrMigrate
end

--- Returns discovery cache entries for current class/spec.
---@return table<number, table>
local function GetBuffBarDiscoveryCache()
    local colors, classID, specID = GetBuffBarDiscoveryContext()
    if not colors or not classID or not specID then
        return {}
    end

    return colors.cache[classID][specID] or {}
end

--- Returns discovery secondary key map for current class/spec.
---@return table<number, number|nil>
local function GetBuffBarDiscoverySecondaryKeyMap()
    local colors, classID, specID = GetBuffBarDiscoveryContext()
    if not colors or not classID or not specID then
        return {}
    end

    return colors.textureMap[classID][specID] or {}
end

---@param reason string|nil
local function RunLayoutPass(reason)
    UpdateFadeAndHiddenStates()

    local scanChanged = RunScanners(reason)

    UpdateAllLayouts()

    if scanChanged then
        ScheduleLayoutUpdate(0, "scanner_changed")
    end
end

--- Schedules a layout update after a delay (debounced).
--- @param delay number Delay in seconds
--- @param reason string|nil Reason for this request
ScheduleLayoutUpdate = function(delay, reason)
    if _layoutPending then
        return
    end

    _layoutPending = true
    C_Timer.After(delay or 0, function()
        _layoutPending = false
        RunLayoutPass(reason or "scheduled")
    end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Registers an ECMFrame to receive layout update events.
--- @param frame ECMFrame The frame to register
local function RegisterFrame(frame)
    assert(frame and type(frame) == "table" and frame.IsECMFrame, "RegisterFrame: invalid ECMFrame")
    assert(_ecmFrames[frame.Name] == nil, "RegisterFrame: frame with name '" .. frame.Name .. "' is already registered")
    _ecmFrames[frame.Name] = frame
    ECM.Log("Layout", "Frame registered", frame.Name)
end

--- Unregisters an ECMFrame from layout update events.
--- @param frame ECMFrame The frame to unregister
local function UnregisterFrame(frame)
    if not frame or type(frame) ~= "table" then
        return
    end

    local name = frame.Name
    if not name or _ecmFrames[name] ~= frame then
        return
    end

    _ecmFrames[name] = nil
    ECM.Log("Layout", "Frame unregistered", name)
end

--- Rebinds config references for all registered ECMFrames.
--- @param configRoot table|nil Active profile root
local function SetAllConfigs(configRoot)
    local root = configRoot or (ECM.db and ECM.db.profile)
    if not root then
        return
    end

    for _, ecmFrame in pairs(_ecmFrames) do
        if ecmFrame and ecmFrame.SetConfig then
            ecmFrame:SetConfig(root)
        end
    end

    ScheduleLayoutUpdate(0, "set_all_configs")
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

-- Register all layout events
for eventName in pairs(LAYOUT_EVENTS) do
    eventFrame:RegisterEvent(eventName)
end
eventFrame:RegisterEvent("CVAR_UPDATE")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and arg1 ~= "player" then
        return
    end

    -- Handle CVAR_UPDATE specially
    if event == "CVAR_UPDATE" then
        if arg1 == "cooldownViewerEnabled" then
            ScheduleLayoutUpdate(0, event)
        end
        return
    end

    local config = LAYOUT_EVENTS[event]
    if not config then
        return
    end

    -- Track combat state
    if config.combatChange then
        _inCombat = (event == "PLAYER_REGEN_DISABLED")
    end

    -- Schedule update with delay
    if config.delay and config.delay > 0 then
        C_Timer.After(config.delay, function()
            RunLayoutPass(event)
        end)
    else
        RunLayoutPass(event)
    end
end)

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

RegisterScanner(C.SCANNER_BUFFBARS_DISCOVERY, RefreshBuffBarDiscovery)

ECM.RegisterFrame = RegisterFrame
ECM.UnregisterFrame = UnregisterFrame
ECM.ScheduleLayoutUpdate = ScheduleLayoutUpdate
ECM.SetAllConfigs = SetAllConfigs
ECM.RegisterScanner = RegisterScanner
ECM.UnregisterScanner = UnregisterScanner
ECM.RefreshBuffBarDiscovery = RefreshBuffBarDiscovery
ECM.GetBuffBarDiscoveryCache = GetBuffBarDiscoveryCache
ECM.GetBuffBarDiscoverySecondaryKeyMap = GetBuffBarDiscoverySecondaryKeyMap
