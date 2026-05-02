-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

---@class ECM_Addon : AceAddon Core addon object (AceAddon instance).
---@field db AceDBObject-3.0 AceDB database handle.
---@field _addonCompartmentRegistered boolean Whether the addon compartment entry has been registered.
---@field _openOptionsAfterCombat boolean Whether to open options after leaving combat.

local ADDON_NAME, ns = ...
local mod = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "LibEvent-1.0")
mod:SetDefaultModuleLibraries("LibEvent-1.0")
ns.Addon = mod
assert(ns.Constants, "Constants.lua must be loaded before ECM.lua")
assert(ns.defaults, "Defaults.lua must be loaded before ECM.lua")
assert(ns.Migration, "Migration.lua must be loaded before ECM.lua")
assert(ns.BarMixin, "BarMixin.lua must be loaded before ECM.lua")
assert(ns.EditMode, "BarMixin.lua must initialize EditMode before ECM.lua")

local LibConsole = LibStub("LibConsole-1.0")
local LSM = LibStub("LibSharedMedia-3.0", true)
local C = ns.Constants
local L = ns.L

--- Returns the global config section. Standalone accessor for non-module callers.
---@return table|nil
function ns.GetGlobalConfig()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    return profile and profile[C.CONFIG_SECTION_GLOBAL]
end

--- Returns whether debug mode is enabled.
function ns.IsDebugEnabled()
    local gc = ns.GetGlobalConfig()
    return gc and gc.debug
end

--- Returns whether the player is a Death Knight.
function ns.IsDeathKnight()
    local _, class = UnitClass("player")
    return class == "DEATHKNIGHT"
end

local function getAddonVersion()
    return C_AddOns.GetAddOnMetadata(ADDON_NAME, C.ADDON_METADATA_VERSION_KEY)
end

local function safeStrTostring(x)
    if x == nil then return "nil" end
    return issecretvalue(x) and "[secret]" or tostring(x)
end

local function safeTableTostring(tbl, depth, seen)
    if issecrettable(tbl) then return "[secrettable]" end
    if seen[tbl] then return "<cycle>" end
    if depth >= C.TOSTRING_MAX_DEPTH then return "{...}" end

    seen[tbl] = true

    local ok, pairsOrErr = pcall(function()
        local parts = {}
        local count = 0

        for k, x in pairs(tbl) do
            count = count + 1
            if count > C.TOSTRING_MAX_ITEMS then
                parts[#parts + 1] = "..."
                break
            end

            local keyStr = issecretvalue(k) and "[secret]" or tostring(k)
            local valueStr = type(x) == "table" and safeTableTostring(x, depth + 1, seen) or safeStrTostring(x)
            parts[#parts + 1] = keyStr .. "=" .. valueStr
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end)

    if not ok then
        return "<table_error>"
    end

    return pairsOrErr
end

function ns.ToString(v)
    if type(v) == "table" then
        return safeTableTostring(v, 0, {})
    end
    return safeStrTostring(v)
end

function ns.DebugAssert(condition, message, data)
    if not ns.IsDebugEnabled() then
        return
    end

    if data and not condition and DevTool and DevTool.AddData then
        pcall(DevTool.AddData, DevTool, data, "|cff" .. C.DEBUG_COLOR .. "[ASSERT]|r " .. message)
    end
    assert(condition, message)
end

function ns.CloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = ns.CloneValue(v)
    end
    return copy
end

ns.Print = LibConsole:NewPrinter(function(message)
    print(ns.ColorUtil.Sparkle(L["ADDON_ABRV"] .. ":") .. " " .. message)
end)

function ns.Log(module, message, data)
    if not ns.IsDebugEnabled() then
        return
    end

    local coloredPrefix = "|cff" .. C.DEBUG_COLOR .. "[" .. L["ADDON_ABRV"]
        .. (module and (" " .. module) or "") .. "]|r "

    if DevTool and DevTool.AddData then
        pcall(DevTool.AddData, DevTool, {
            module = module or "nil",
            message = message,
            timestamp = GetTime(),
            data = data and ns.ToString(data),
        }, coloredPrefix .. message)
    end

    local cfg = ns.GetGlobalConfig()
    if cfg and cfg.debugToChat then
        print(coloredPrefix .. message)
    end
end

--- Shows a confirmation popup and reloads the UI on accept.
--- ReloadUI is blocked in combat.
---@param text string
---@param onAccept fun()|nil
---@param onCancel fun()|nil
function mod:ConfirmReloadUI(text, onAccept, onCancel)
    if InCombatLockdown() then
        ns.Print(L["RELOAD_BLOCKED_COMBAT"])
        return
    end

    if not StaticPopupDialogs[C.POPUP_CONFIRM_RELOAD_UI] then
        StaticPopupDialogs[C.POPUP_CONFIRM_RELOAD_UI] = {
            text = L["RELOAD_UI_PROMPT"],
            button1 = YES or "Yes",
            button2 = NO or "No",
            OnAccept = function(_, data)
                if data and data.onAccept then
                    data.onAccept()
                end
                ReloadUI()
            end,
            OnCancel = function(_, data)
                if data and data.onCancel then
                    data.onCancel()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = C.POPUP_PREFERRED_INDEX,
        }
    end

    StaticPopupDialogs[C.POPUP_CONFIRM_RELOAD_UI].text = text or L["RELOAD_UI_PROMPT"]
    StaticPopup_Show(C.POPUP_CONFIRM_RELOAD_UI, nil, nil, { onAccept = onAccept, onCancel = onCancel })
end

--- Handles slash command input.
---@param input string|nil
function mod:ChatCommand(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

    if cmd == "help" or cmd == "h" then
        ns.Print(L["CMD_HELP_CLEARSEEN"])
        ns.Print(L["CMD_HELP_DEBUG"])
        ns.Print(L["CMD_HELP_EVENTS"])
        ns.Print(L["CMD_HELP_EVENTS_RESET"])
        ns.Print(L["CMD_HELP_HELP"])
        ns.Print(L["CMD_HELP_MIGRATION"])
        ns.Print(L["CMD_HELP_MIGRATION_LOG"])
        ns.Print(L["CMD_HELP_MIGRATION_ROLLBACK"])
        ns.Print(L["CMD_HELP_OPTIONS"])
        ns.Print(L["CMD_HELP_REFRESH"])
        return
    end

    if cmd == "rl" or cmd == "reload" or cmd == "refresh" then
        ns.Runtime.ScheduleLayoutUpdate(0, "ChatCommand")
        ns.Print(L["REFRESHING_ALL_MODULES"])
        return
    end

    if cmd == "migration" then
        local subcmd, subarg = arg:match("^(%S*)%s*(.-)%s*$")
        if subcmd == "log" then
            local text = ns.Migration.GetLogText()
            if not text then
                ns.Print(L["MIGRATION_LOG_EMPTY"])
            else
                self:ShowMigrationLogDialog(text)
            end
            return
        end

        if subcmd == "rollback" then
            local n = tonumber(subarg)
            if not n then
                ns.Print(L["MIGRATION_ROLLBACK_USAGE"])
                return
            end
            if n == 0 then
                ns.Print(L["VERSION_ZERO_INVALID"])
                return
            end
            if n == -1 then
                n = ns.Constants.CURRENT_SCHEMA_VERSION - 1
            end
            local ok, message = ns.Migration.ValidateRollback(n)
            if not ok then
                ns.Print(message)
                return
            end
            self:ConfirmReloadUI(message, function()
                ns.Migration.Rollback(n)
            end)
            return
        end

        ns.Migration.PrintInfo()
        return
    end

    if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
        if InCombatLockdown() then
            ns.Print(L["OPTIONS_BLOCKED_COMBAT"])
            self._openOptionsAfterCombat = true
            return
        end

        local optionsModule = self:GetModule("Options", true)
        if optionsModule then
            optionsModule:OpenOptions()
        end
        return
    end

    if cmd == "events" then
        self:HandleEventsCommand(arg)
        return
    end

    local gc = ns.GetGlobalConfig()
    if not gc then
        return
    end

    if cmd == "debug" then
        local newVal
        if arg == "" or arg == "toggle" then
            newVal = not gc.debug
        elseif arg == "on" then
            newVal = true
        elseif arg == "off" then
            newVal = false
        else
            ns.Print(L["DEBUG_USAGE"])
            return
        end
        gc.debug = newVal
        ns.Print(L["DEBUG_STATUS"] .. " " .. (gc.debug and L["DEBUG_ON"] or L["DEBUG_OFF"]))
        return
    end

    if cmd == "clearseen" then
        gc.releasePopupSeenVersion = nil
        ns.Print(L["SEEN_CLEARED"])
        ReloadUI()
        return
    end
end

function mod:HandleEventsCommand(arg)
    if arg == "reset" then
        self:ResetEventStats()
        for _, m in self:IterateModules() do
            if m.ResetEventStats then
                m:ResetEventStats()
            end
        end
        ns.Print(L["EVENTS_RESET"])
        return
    end

    -- Aggregate stats from the addon and all its modules.
    local merged = {}
    for event, count in pairs(self:GetEventStats()) do
        merged[event] = (merged[event] or 0) + count
    end
    for _, m in self:IterateModules() do
        if m.GetEventStats then
            for event, count in pairs(m:GetEventStats()) do
                merged[event] = (merged[event] or 0) + count
            end
        end
    end

    -- Sort descending by count.
    local sorted = {}
    for event, count in pairs(merged) do
        sorted[#sorted + 1] = { event = event, count = count }
    end

    if #sorted == 0 then
        ns.Print(L["EVENTS_NONE"])
        return
    end

    table.sort(sorted, function(a, b)
        return a.count > b.count
    end)

    ns.Print(L["EVENTS_HEADER"])
    for i = 1, #sorted do
        ns.Print("  " .. sorted[i].event .. ": " .. sorted[i].count)
    end
end

function mod:HandleOpenOptionsAfterCombat()
    if not self._openOptionsAfterCombat then
        return
    end

    self._openOptionsAfterCombat = nil

    local optionsModule = self:GetModule("Options", true)
    if optionsModule then
        optionsModule:OpenOptions()
    end
end

function mod:GetECMModule(moduleName, silent)
    local module = self[moduleName] or ns[moduleName]
    if not module and not silent then
        ns.Print(L["MODULE_NOT_FOUND"] .. " " .. moduleName)
    end
    return module
end

function mod:OnInitialize()
    -- Set up versioned SV store and point the active key at the current version.
    ns.Migration.PrepareDatabase()

    self.db = LibStub("AceDB-3.0"):New(C.ACTIVE_SV_KEY, ns.defaults, true)

    ns.Migration.Run(self.db.profile)

    ns.Migration.FlushLog()

    -- Register bundled fonts with LibSharedMedia
    if LSM then
        pcall(
            LSM.Register,
            LSM,
            "font",
            "Expressway",
            "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf"
        )
        pcall(
            LSM.Register,
            LSM,
            "font",
            "Cabin",
            "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Cabin.ttf"
        )
    end

    local chatHandler = function(input) mod:ChatCommand(input) end
    LibConsole:RegisterCommand("enhancedcooldownmanager", chatHandler)
    LibConsole:RegisterCommand("ecm", chatHandler)
end

--- Enables the addon and ensures Blizzard's cooldown viewer is turned on.
function mod:OnEnable()
    C_CVar.SetCVar("cooldownViewerEnabled", "1")
    if not self._addonCompartmentRegistered and AddonCompartmentFrame then
        local ok = pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
            text = ns.ColorUtil.Sparkle(L["ADDON_NAME"]),
            icon = C.ADDON_ICON_TEXTURE,
            notCheckable = true,
            func = function()
                self:ChatCommand("options")
            end,
        })
        self._addonCompartmentRegistered = ok
    end

    ns.Runtime.OnCombatEnd = function()
        self:HandleOpenOptionsAfterCombat()
    end

    ns.Runtime.Enable(self)

    -- Re-evaluate module enable/disable states on profile switch.
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChangedHandler")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChangedHandler")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChangedHandler")

    local version = getAddonVersion()

    if type(version) == "string" and version:lower():find(C.VERSION_TAG_BETA, 1, true) ~= nil then
        ns.Print(L["BETA_LOGIN_MESSAGE"])
    end

    self:ShowReleasePopup()
end

--- Re-evaluates module enable/disable states after a profile change and refreshes layout.
function mod:OnProfileChangedHandler()
    ns.Migration.Run(self.db.profile)
    ns.Runtime.Enable(self)
    ns.Runtime.ScheduleLayoutUpdate(0, "ProfileChanged")
end

function mod:OnDisable()
    ns.Runtime.Disable(self)
end
