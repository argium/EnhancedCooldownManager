-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

StaticPopupDialogs["ECM_CONFIRM_DELETE_PROFILE"] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["ECM_CONFIRM_RESET_PROFILE"] = {
    text = "Are you sure you want to reset the current profile to defaults?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local ProfileOptions = {}

function ProfileOptions.RegisterSettings(SB)
    local cat = SB.CreateSubcategory("Profiles")

    -- Switch Profile
    SB.Header("Active Profile")

    local switchSetting = Settings.RegisterProxySetting(cat, "ECM_ProfileSwitch",
        Settings.VarType.String, "Switch Profile",
        mod.db:GetCurrentProfile(),
        function() return mod.db:GetCurrentProfile() end,
        function(value) mod.db:SetProfile(value) end
    )

    Settings.CreateDropdown(cat, switchSetting, function()
        local container = Settings.CreateControlTextContainer()
        for _, name in ipairs(mod.db:GetProfiles()) do
            container:Add(name, name)
        end
        return container:GetData()
    end, "Select a profile to switch to.")

    -- New Profile
    SB.Button({
        name = "Create a new profile",
        buttonText = "New Profile",
        tooltip = "Create a new profile using your current character name.",
        onClick = function()
            local newName = UnitName("player") .. " - " .. date("%H%M%S")
            switchSetting:SetValue(newName)
        end,
    })

    -- Copy From
    SB.Header("Profile Actions")

    local selectedCopyProfile = nil

    local copySetting = Settings.RegisterProxySetting(cat, "ECM_ProfileCopy",
        Settings.VarType.String, "Copy From", "",
        function() return selectedCopyProfile or "" end,
        function(value) selectedCopyProfile = value end
    )

    Settings.CreateDropdown(cat, copySetting, function()
        local container = Settings.CreateControlTextContainer()
        local current = mod.db:GetCurrentProfile()
        for _, name in ipairs(mod.db:GetProfiles()) do
            if name ~= current then
                container:Add(name, name)
            end
        end
        return container:GetData()
    end, "Select a profile to copy settings from.")

    SB.Button({
        name = "Apply copy from selected profile",
        buttonText = "Copy",
        tooltip = "Copy all settings from the selected profile into the current one.",
        onClick = function()
            if not selectedCopyProfile or selectedCopyProfile == "" then return end
            mod.db:CopyProfile(selectedCopyProfile)
            selectedCopyProfile = nil
        end,
    })

    -- Delete Profile
    local selectedDeleteProfile = nil

    local deleteSetting = Settings.RegisterProxySetting(cat, "ECM_ProfileDelete",
        Settings.VarType.String, "Delete Profile", "",
        function() return selectedDeleteProfile or "" end,
        function(value) selectedDeleteProfile = value end
    )

    Settings.CreateDropdown(cat, deleteSetting, function()
        local container = Settings.CreateControlTextContainer()
        local current = mod.db:GetCurrentProfile()
        for _, name in ipairs(mod.db:GetProfiles()) do
            if name ~= current then
                container:Add(name, name)
            end
        end
        return container:GetData()
    end, "Select a profile to delete.")

    SB.Button({
        name = "Delete the selected profile",
        buttonText = "Delete",
        tooltip = "Delete the selected profile. The active profile cannot be deleted.",
        onClick = function()
            if not selectedDeleteProfile or selectedDeleteProfile == "" then return end
            local name = selectedDeleteProfile
            local dialog = StaticPopupDialogs["ECM_CONFIRM_DELETE_PROFILE"]
            dialog.text = string.format("Are you sure you want to delete the profile '%s'?", name)
            dialog.OnAccept = function()
                mod.db:DeleteProfile(name)
                selectedDeleteProfile = nil
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
            mod.db:ResetProfile()
        end,
    })

    -- Import / Export
    SB.Header("Import / Export")

    SB.Button({
        name = "Import a profile from a string",
        buttonText = "Import",
        tooltip = "Paste a previously exported profile string to import settings.",
        onClick = function()
            if InCombatLockdown() then
                mod:Print("Cannot import during combat (reload blocked)")
                return
            end
            mod:ShowImportDialog()
        end,
    })

    SB.Button({
        name = "Export the current profile as a string",
        buttonText = "Export",
        tooltip = "Generate a shareable string that can be imported on another character.",
        onClick = function()
            local exportString, err = ECM.ImportExport.ExportCurrentProfile()
            if not exportString then
                mod:Print("Export failed: " .. (err or "Unknown error"))
                return
            end
            mod:ShowExportDialog(exportString)
        end,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "Profile", ProfileOptions)
