-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

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
local function createProfilePicker(SB, cat, variable, name, tooltip, valuesGenerator)
    local selected = nil
    local setting = Settings.RegisterProxySetting(cat, variable, Settings.VarType.String, name, "", function()
        return selected or ""
    end, function(value)
        selected = value
    end)
    Settings.CreateDropdown(cat, setting, valuesGenerator, tooltip)
    return setting, function()
        return selected
    end, function()
        selected = nil
    end
end

function ProfileOptions.RegisterSettings(SB)
    local cat = SB.CreateSubcategory("Profiles")

    -- Switch Profile
    SB.Header("Active Profile")

    local switchSetting = Settings.RegisterProxySetting(
        cat,
        "ECM_ProfileSwitch",
        Settings.VarType.String,
        "Switch Profile",
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
        name = "Create a new profile",
        buttonText = "New Profile",
        tooltip = "Create a new profile using your current character name.",
        onClick = function()
            switchSetting:SetValue(UnitName("player") .. " - " .. date("%H%M%S"))
        end,
    })

    -- Copy / Delete
    SB.Header("Profile Actions")

    local function otherProfilesGenerator()
        local container = Settings.CreateControlTextContainer()
        local current = ns.Addon.db:GetCurrentProfile()
        for _, name in ipairs(ns.Addon.db:GetProfiles()) do
            if name ~= current then
                container:Add(name, name)
            end
        end
        return container:GetData()
    end

    local _, getCopyProfile, clearCopyProfile = createProfilePicker(
        SB,
        cat,
        "ECM_ProfileCopy",
        "Copy From",
        "Select a profile to copy settings from.",
        otherProfilesGenerator
    )

    SB.Button({
        name = "Apply copy from selected profile",
        buttonText = "Copy",
        tooltip = "Copy all settings from the selected profile into the current one.",
        onClick = function()
            local profile = getCopyProfile()
            if not profile or profile == "" then
                return
            end
            ns.Addon.db:CopyProfile(profile)
            clearCopyProfile()
        end,
    })

    local _, getDeleteProfile, clearDeleteProfile = createProfilePicker(
        SB,
        cat,
        "ECM_ProfileDelete",
        "Delete Profile",
        "Select a profile to delete.",
        otherProfilesGenerator
    )

    SB.Button({
        name = "Delete the selected profile",
        buttonText = "Delete",
        tooltip = "Delete the selected profile. The active profile cannot be deleted.",
        onClick = function()
            local profile = getDeleteProfile()
            if not profile or profile == "" then
                return
            end
            local dialog = StaticPopupDialogs["ECM_CONFIRM_DELETE_PROFILE"]
            dialog.text = string.format("Are you sure you want to delete the profile '%s'?", profile)
            dialog.OnAccept = function()
                ns.Addon.db:DeleteProfile(profile)
                clearDeleteProfile()
            end
            StaticPopup_Show("ECM_CONFIRM_DELETE_PROFILE")
        end,
    })

    -- Reset
    SB.Header("Reset")

    SB.Button({
        name = "Reset current profile to defaults",
        buttonText = "Reset Profile",
        tooltip = "Reset the current profile back to default settings. This cannot be undone.",
        confirm = "Are you sure you want to reset the current profile to defaults?",
        onClick = function()
            ns.Addon.db:ResetProfile()
        end,
    })

    -- Import / Export
    SB.Header("Import / Export")

    SB.Button({
        name = "Import profile from clipboard",
        buttonText = "Import",
        tooltip = "Paste a previously exported profile string to import settings.",
        onClick = function()
            if InCombatLockdown() then
                ns.Addon:Print("Cannot import during combat (reload blocked)")
                return
            end
            ns.Addon:ShowImportDialog()
        end,
    })

    SB.Button({
        name = "Export profile to clipboard",
        buttonText = "Export",
        tooltip = "Generate a shareable string that can be imported on another character.",
        onClick = function()
            local exportString, err = ECM.ImportExport.ExportCurrentProfile()
            if not exportString then
                ns.Addon:Print("Export failed: " .. (err or "Unknown error"))
                return
            end
            ns.Addon:ShowExportDialog(exportString)
        end,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "Profile", ProfileOptions)
