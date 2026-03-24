-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ECM.L

StaticPopupDialogs["ECM_CONFIRM_DELETE_PROFILE"] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local ProfileOptions = {}

--- Creates a proxy-backed dropdown for transient profile selection (not stored in SavedVars).
local function createProfilePicker(cat, variable, name, tooltip, valuesGenerator)
    local selected = nil
    local onSelectionChanged = nil

    local function notifySelectionChanged()
        if onSelectionChanged then
            onSelectionChanged(selected)
        end
    end

    local setting = Settings.RegisterProxySetting(cat, variable, Settings.VarType.String, name, "", function()
        return selected or ""
    end, function(value)
        selected = value
        notifySelectionChanged()
    end)
    Settings.CreateDropdown(cat, setting, valuesGenerator, tooltip)
    return setting, function()
        return selected
    end, function()
        selected = nil
        notifySelectionChanged()
    end, function(callback)
        onSelectionChanged = callback
        notifySelectionChanged()
    end
end

function ProfileOptions.RegisterSettings(SB)
    local cat = SB.CreateSubcategory(L["PROFILES"])
    local function isBlankSelection(getSelection)
        local selection = getSelection()
        return not selection or selection == ""
    end

    -- Switch Profile
    SB.Header(L["ACTIVE_PROFILE"])

    local switchSetting = Settings.RegisterProxySetting(
        cat,
        "ECM_ProfileSwitch",
        Settings.VarType.String,
        L["SWITCH_PROFILE"],
        ns.Addon.db:GetCurrentProfile(),
        function()
            return ns.Addon.db:GetCurrentProfile()
        end,
        function(value)
            ns.Addon.db:SetProfile(value)
        end
    )

    Settings.CreateDropdown(cat, switchSetting, function()
        local container = Settings.CreateControlTextContainer()
        for _, name in ipairs(ns.Addon.db:GetProfiles()) do
            container:Add(name, name)
        end
        return container:GetData()
    end, "Select a profile to switch to.")

    SB.Button({
        name = "",
        buttonText = L["NEW_PROFILE"],
        tooltip = L["NEW_PROFILE_DESC"],
        onClick = function()
            switchSetting:SetValue(UnitName("player") .. " - " .. date("%H%M%S"))
        end,
    })

    -- Copy / Delete
    SB.Header(L["PROFILE_ACTIONS"])

    local function otherProfilesGenerator()
        local container = Settings.CreateControlTextContainer()
        container:Add("", "")
        local current = ns.Addon.db:GetCurrentProfile()
        for _, name in ipairs(ns.Addon.db:GetProfiles()) do
            if name ~= current then
                container:Add(name, name)
            end
        end
        return container:GetData()
    end

    local _, getCopyProfile, clearCopyProfile, setCopySelectionChanged =
        createProfilePicker(cat, "ECM_ProfileCopy", L["COPY_FROM"], L["COPY_FROM_DESC"], otherProfilesGenerator)

    local copyButton = SB.Button({
        name = "",
        buttonText = L["COPY"],
        tooltip = L["COPY_DESC"],
        disabled = function()
            return isBlankSelection(getCopyProfile)
        end,
        onClick = function()
            local profile = getCopyProfile()
            if not profile or profile == "" then
                return
            end
            ns.Addon.db:CopyProfile(profile)
            clearCopyProfile()
        end,
    })
    setCopySelectionChanged(function(selection)
        if copyButton and copyButton.SetEnabled then
            copyButton:SetEnabled(selection ~= nil and selection ~= "")
        end
    end)

    local _, getDeleteProfile, clearDeleteProfile, setDeleteSelectionChanged = createProfilePicker(
        cat,
        "ECM_ProfileDelete",
        L["DELETE_PROFILE"],
        L["DELETE_PROFILE_SELECT_DESC"],
        otherProfilesGenerator
    )

    local deleteButton = SB.Button({
        name = "",
        buttonText = L["DELETE"],
        tooltip = L["DELETE_DESC"],
        disabled = function()
            return isBlankSelection(getDeleteProfile)
        end,
        onClick = function()
            local profile = getDeleteProfile()
            if not profile or profile == "" then
                return
            end
            local dialog = StaticPopupDialogs["ECM_CONFIRM_DELETE_PROFILE"]
            dialog.text = string.format(L["DELETE_PROFILE_CONFIRM"], profile)
            dialog.OnAccept = function()
                ns.Addon.db:DeleteProfile(profile)
                clearDeleteProfile()
            end
            StaticPopup_Show("ECM_CONFIRM_DELETE_PROFILE")
        end,
    })
    setDeleteSelectionChanged(function(selection)
        if deleteButton and deleteButton.SetEnabled then
            deleteButton:SetEnabled(selection ~= nil and selection ~= "")
        end
    end)

    -- Reset
    SB.Header(L["RESET"])

    SB.Button({
        name = L["RESET_PROFILE"],
        buttonText = L["RESET_PROFILE_BUTTON"],
        tooltip = L["RESET_PROFILE_DESC"],
        confirm = L["RESET_PROFILE_CONFIRM"],
        onClick = function()
            ns.Addon.db:ResetProfile()
        end,
    })

    -- Import / Export
    SB.Header(L["IMPORT_EXPORT"])

    SB.Button({
        name = L["IMPORT_PROFILE"],
        buttonText = L["IMPORT"],
        tooltip = L["IMPORT_DESC"],
        onClick = function()
            if InCombatLockdown() then
                ECM.Print(L["CANNOT_IMPORT_IN_COMBAT"])
                return
            end
            ns.Addon:ShowImportDialog()
        end,
    })

    SB.Button({
        name = L["EXPORT_PROFILE"],
        buttonText = L["EXPORT"],
        tooltip = L["EXPORT_DESC"],
        onClick = function()
            local exportString, err = ECM.ImportExport.ExportCurrentProfile()
            if not exportString then
                ECM.Print(string.format(L["EXPORT_FAILED"], err or "Unknown error"))
                return
            end
            ns.Addon:ShowExportDialog(exportString)
        end,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "Profile", ProfileOptions)
