-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ECM.L

StaticPopupDialogs["ECM_NEW_PROFILE"] = {
    text = L["NEW_PROFILE_PROMPT"],
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    OnAccept = function() end,
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
            StaticPopupDialogs["ECM_NEW_PROFILE"].OnAccept(parent)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["ECM_CONFIRM_COPY_PROFILE"] = ECM.OptionUtil.MakeConfirmDialog("")
StaticPopupDialogs["ECM_CONFIRM_DELETE_PROFILE"] = ECM.OptionUtil.MakeConfirmDialog("")

local ProfileOptions = {}

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

--- Creates a proxy-backed dropdown for transient profile selection (not stored in SavedVars).
local function createProfilePicker(cat, variable, name, tooltip, valuesGenerator)
    local selected = getPreferredProfileSelection(valuesGenerator)

    local function ensureSelection()
        if not selected or selected == "" then
            selected = getPreferredProfileSelection(valuesGenerator)
        end
    end

    local setting = Settings.RegisterProxySetting(cat, variable, Settings.VarType.String, name, selected, function()
        ensureSelection()
        return selected
    end, function(value)
        selected = value
    end)
    Settings.CreateDropdown(cat, setting, valuesGenerator, tooltip)
    ensureSelection()
    return setting, function()
        ensureSelection()
        return selected
    end, function()
        selected = getPreferredProfileSelection(valuesGenerator)
    end
end

function ProfileOptions.RegisterSettings(SB)
    local cat = SB.CreateSubcategory(L["PROFILES"])

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
    end, L["SWITCH_PROFILE_DESC"])

    SB.Button({
        name = L["NEW_PROFILE"],
        buttonText = L["NEW_PROFILE"],
        tooltip = L["NEW_PROFILE_DESC"],
        onClick = function()
            local dialog = StaticPopupDialogs["ECM_NEW_PROFILE"]
            dialog.OnAccept = function(self)
                local editBox = self and (self.EditBox or self.editBox)
                if not editBox then
                    return
                end
                local name = strtrim(editBox:GetText())
                if name ~= "" then
                    switchSetting:SetValue(name)
                end
            end
            StaticPopup_Show("ECM_NEW_PROFILE")
        end,
    })

    -- Copy / Delete
    SB.Header(L["PROFILE_ACTIONS"])

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

    local _, getCopyProfile, clearCopyProfile =
        createProfilePicker(cat, "ECM_ProfileCopy", L["COPY_FROM"], L["COPY_FROM_DESC"], otherProfilesGenerator)

    SB.Button({
        name = L["COPY"],
        buttonText = L["COPY"],
        tooltip = L["COPY_DESC"],
        onClick = function()
            local profile = getCopyProfile()
            if not profile or profile == "" then
                return
            end
            local dialog = StaticPopupDialogs["ECM_CONFIRM_COPY_PROFILE"]
            dialog.text = string.format(L["COPY_PROFILE_CONFIRM"], profile)
            dialog.OnAccept = function()
                ns.Addon.db:CopyProfile(profile)
                clearCopyProfile()
            end
            StaticPopup_Show("ECM_CONFIRM_COPY_PROFILE")
        end,
    })

    local _, getDeleteProfile, clearDeleteProfile = createProfilePicker(
        cat,
        "ECM_ProfileDelete",
        L["DELETE_PROFILE"],
        L["DELETE_PROFILE_SELECT_DESC"],
        otherProfilesGenerator
    )

    SB.Button({
        name = L["DELETE"],
        buttonText = L["DELETE"],
        tooltip = L["DELETE_DESC"],
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
