-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

local function getPopupEditBox(frame) return frame and (frame.EditBox or frame.editBox) end

StaticPopupDialogs["ECM_NEW_PROFILE"] = {
    text = L["NEW_PROFILE_PROMPT"],
    button1 = L["CREATE"],
    button2 = L["DONT_CREATE"],
    hasEditBox = true,
    OnAccept = function(self, data)
        local editBox = getPopupEditBox(self)
        local name = strtrim(editBox and editBox:GetText() or "")
        if name ~= "" and data and data.onAccept then
            data.onAccept(name)
        end
    end,
    OnShow = function(self)
        local editBox = getPopupEditBox(self)
        if not editBox then
            return
        end
        editBox:SetText(UnitName("player") .. " - " .. date("%H%M%S"))
        editBox:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent.button1:IsEnabled() then
            parent:Hide()
            local dialog = StaticPopupDialogs["ECM_NEW_PROFILE"]
            dialog.OnAccept(parent, parent.data)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["ECM_CONFIRM_COPY_PROFILE"] = ns.OptionUtil.MakeConfirmDialog(
    L["COPY_PROFILE_CONFIRM"],
    L["COPY"],
    L["DONT_COPY"]
)
StaticPopupDialogs["ECM_CONFIRM_DELETE_PROFILE"] = ns.OptionUtil.MakeConfirmDialog(
    L["DELETE_PROFILE_CONFIRM"],
    L["DELETE"],
    L["DONT_DELETE"]
)

local ProfileOptions = {}
ns.ProfileOptions = ProfileOptions

local function getPreferredProfileSelection(valuesGenerator)
    local values = valuesGenerator()
    local first = nil

    for _, entry in ipairs(values) do
        local value = entry.value
        if value and value ~= "" then
            if not first then
                first = value
            end
            if value == "Default" then
                return value
            end
        end
    end

    return first or ""
end

--- Creates a handler-backed dropdown for transient profile selection (not stored in SavedVars).
local function createProfilePickerRow(variable, name, tooltip, valuesGenerator)
    local selected

    local function ensureSelection()
        if selected == nil or selected == "" then
            selected = getPreferredProfileSelection(valuesGenerator)
        end

        return selected
    end

    local function values()
        local map = {}
        for _, entry in ipairs(valuesGenerator()) do
            map[entry.value] = entry.label
        end
        return map
    end

    return {
        type = "dropdown",
        key = variable,
        name = name,
        tooltip = tooltip,
        default = "",
        scrollHeight = 240,
        values = values,
        get = function()
            return ensureSelection()
        end,
        set = function(value)
            selected = value
        end,
    }, function()
        return ensureSelection()
    end, function()
        selected = nil
    end
end

local function otherProfilesGenerator()
    local container = Settings.CreateControlTextContainer()
    local db = ns.Addon.db

    local current = db:GetCurrentProfile()
    for _, name in ipairs(db:GetProfiles()) do
        if name ~= current then
            container:Add(name, name)
        end
    end
    return container:GetData()
end

local copyProfileRow, getCopyProfile, resetCopyProfile = createProfilePickerRow(
    "ProfileCopy",
    L["COPY_FROM"],
    L["COPY_FROM_DESC"],
    otherProfilesGenerator
)

local deleteProfileRow, getDeleteProfile, resetDeleteProfile = createProfilePickerRow(
    "ProfileDelete",
    L["DELETE_PROFILE"],
    L["DELETE_PROFILE_SELECT_DESC"],
    otherProfilesGenerator
)

ProfileOptions.key = "profile"
ProfileOptions.name = L["PROFILES"]
ProfileOptions.pages = {
    {
        key = "main",
        hideDefaults = true,
        rows = {
    { type = "header", name = L["ACTIVE_PROFILE"] },
    {
        type = "dropdown",
        key = "ProfileSwitch",
        name = L["SWITCH_PROFILE"],
        tooltip = L["SWITCH_PROFILE_DESC"],
        default = "",
        scrollHeight = 240,
        values = function()
            local values = {}
            for _, name in ipairs(ns.Addon.db:GetProfiles()) do
                values[name] = name
            end
            return values
        end,
        get = function()
            return ns.Addon.db:GetCurrentProfile()
        end,
        set = function(value)
            ns.Addon.db:SetProfile(value)
        end,
        onSet = function(ctx)
            ctx.page:Refresh()
        end,
    },
    {
        type = "button",
        name = L["NEW_PROFILE"],
        buttonText = L["NEW_PROFILE"],
        tooltip = L["NEW_PROFILE_DESC"],
        onClick = function(ctx)
            StaticPopup_Show("ECM_NEW_PROFILE", nil, nil, {
                onAccept = function(name)
                    ns.Addon.db:SetProfile(name)
                    ctx.page:Refresh()
                end,
            })
        end,
    },
    { type = "header", name = L["PROFILE_ACTIONS"] },
    copyProfileRow,
    {
        type = "button",
        name = L["COPY"],
        buttonText = L["COPY"],
        tooltip = L["COPY_DESC"],
        onClick = function(ctx)
            local profile = getCopyProfile()
            if not profile or profile == "" then
                return
            end
            StaticPopup_Show("ECM_CONFIRM_COPY_PROFILE", profile, nil, {
                onAccept = function()
                    ns.Addon.db:CopyProfile(profile)
                    resetCopyProfile()
                    ctx.page:Refresh()
                end,
            })
        end,
    },
    deleteProfileRow,
    {
        type = "button",
        name = L["DELETE"],
        buttonText = L["DELETE"],
        tooltip = L["DELETE_DESC"],
        onClick = function(ctx)
            local profile = getDeleteProfile()
            if not profile or profile == "" then
                return
            end
            StaticPopup_Show("ECM_CONFIRM_DELETE_PROFILE", profile, nil, {
                onAccept = function()
                    ns.Addon.db:DeleteProfile(profile)
                    resetDeleteProfile()
                    ctx.page:Refresh()
                end,
            })
        end,
    },
    {
        type = "button",
        name = L["RESET_PROFILE_BUTTON"],
        buttonText = L["RESET_PROFILE_BUTTON"],
        tooltip = L["RESET_PROFILE_DESC"],
        confirm = L["RESET_PROFILE_CONFIRM"],
        onClick = function(ctx)
            ns.Addon.db:ResetProfile()
            ctx.page:Refresh()
        end,
    },
    {
        type = "pageActions",
        attachToCategoryHeader = true,
        actions = {
            {
                text = L["IMPORT"],
                tooltip = L["IMPORT_DESC"],
                onClick = function()
                    if InCombatLockdown() then
                        ns.Print(L["CANNOT_IMPORT_IN_COMBAT"])
                        return
                    end
                    ns.Addon:ShowImportDialog()
                end,
            },
            {
                text = L["EXPORT"],
                tooltip = L["EXPORT_DESC"],
                onClick = function()
                    local exportString, err = ns.ImportExport.ExportCurrentProfile()
                    if not exportString then
                        ns.Print(string.format(L["EXPORT_FAILED"], err or "Unknown error"))
                        return
                    end
                    ns.Addon:ShowExportDialog(exportString)
                end,
            },
        },
    },
        },
    },
}
