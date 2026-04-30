-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

StaticPopupDialogs["ECM_NEW_PROFILE"] = {
    text = L["NEW_PROFILE_PROMPT"],
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    OnAccept = function(self, data)
        local editBox = self and (self.EditBox or self.editBox)
        if not editBox then
            return
        end
        local name = strtrim(editBox:GetText())
        if name ~= "" and data and data.onAccept then
            data.onAccept(name)
        end
    end,
    OnShow = function(self)
        local editBox = self.EditBox or self.editBox
        if not editBox then
            return
        end
        editBox:SetText(UnitName("player") .. " - " .. date("%H%M%S"))
        editBox:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local button1 = parent and (parent.button1 or (parent.Buttons and parent.Buttons[1]))
        if not button1 or button1:IsEnabled() then
            parent:Hide()
            local dialog = StaticPopupDialogs["ECM_NEW_PROFILE"]
            if dialog.OnAccept then
                dialog.OnAccept(parent, parent.data)
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["ECM_CONFIRM_COPY_PROFILE"] = ns.OptionUtil.MakeConfirmDialog(L["COPY_PROFILE_CONFIRM"])
StaticPopupDialogs["ECM_CONFIRM_DELETE_PROFILE"] = ns.OptionUtil.MakeConfirmDialog(L["DELETE_PROFILE_CONFIRM"])

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
    local db = ns.Addon and ns.Addon.db
    if not db then
        return container:GetData()
    end

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
        onDefault = function() end,
        onDefaultEnabled = function()
            return false
        end,
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
    { type = "header", name = L["RESET"] },
    {
        type = "button",
        name = L["RESET_PROFILE"],
        buttonText = L["RESET_PROFILE_BUTTON"],
        tooltip = L["RESET_PROFILE_DESC"],
        confirm = L["RESET_PROFILE_CONFIRM"],
        onClick = function(ctx)
            ns.Addon.db:ResetProfile()
            ctx.page:Refresh()
        end,
    },
    { type = "header", name = L["IMPORT_EXPORT"] },
    {
        type = "button",
        name = L["IMPORT_PROFILE"],
        buttonText = L["IMPORT"],
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
        type = "button",
        name = L["EXPORT_PROFILE"],
        buttonText = L["EXPORT"],
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
}
