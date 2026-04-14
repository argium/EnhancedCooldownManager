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
local function createProfilePicker(SB, cat, variable, name, tooltip, valuesGenerator)
    local selected = getPreferredProfileSelection(valuesGenerator)

    local function ensureSelection()
        if not selected or selected == "" then
            selected = getPreferredProfileSelection(valuesGenerator)
        end
    end

    local function values()
        local map = {}
        for _, entry in ipairs(valuesGenerator()) do
            map[entry.value] = entry.label
        end
        return map
    end

    local _, setting = SB.Dropdown({
        category = cat,
        key = variable,
        name = name,
        tooltip = tooltip,
        default = selected,
        scrollHeight = 240,
        values = values,
        get = function()
            ensureSelection()
            return selected
        end,
        set = function(value)
            selected = value
        end,
    })
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
    local function refreshCategory()
        SB.RefreshCategory(cat)
    end

    -- Switch Profile
    SB.Header(L["ACTIVE_PROFILE"])

    local _, switchSetting = SB.Dropdown({
        category = cat,
        key = "ProfileSwitch",
        name = L["SWITCH_PROFILE"],
        tooltip = L["SWITCH_PROFILE_DESC"],
        default = ns.Addon.db:GetCurrentProfile(),
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
            refreshCategory()
        end,
    })

    SB.Button({
        name = L["NEW_PROFILE"],
        buttonText = L["NEW_PROFILE"],
        tooltip = L["NEW_PROFILE_DESC"],
        onClick = function()
            StaticPopup_Show("ECM_NEW_PROFILE", nil, nil, {
                onAccept = function(name)
                    switchSetting:SetValue(name)
                    refreshCategory()
                end,
            })
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
        createProfilePicker(SB, cat, "ProfileCopy", L["COPY_FROM"], L["COPY_FROM_DESC"], otherProfilesGenerator)

    SB.Button({
        name = L["COPY"],
        buttonText = L["COPY"],
        tooltip = L["COPY_DESC"],
        onClick = function()
            local profile = getCopyProfile()
            if not profile or profile == "" then
                return
            end
            StaticPopup_Show("ECM_CONFIRM_COPY_PROFILE", profile, nil, {
                onAccept = function()
                    ns.Addon.db:CopyProfile(profile)
                    clearCopyProfile()
                    refreshCategory()
                end,
            })
        end,
    })

    local _, getDeleteProfile, clearDeleteProfile = createProfilePicker(
        SB,
        cat,
        "ProfileDelete",
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
            StaticPopup_Show("ECM_CONFIRM_DELETE_PROFILE", profile, nil, {
                onAccept = function()
                    ns.Addon.db:DeleteProfile(profile)
                    clearDeleteProfile()
                    refreshCategory()
                end,
            })
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
                ns.Print(L["CANNOT_IMPORT_IN_COMBAT"])
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
            local exportString, err = ns.ImportExport.ExportCurrentProfile()
            if not exportString then
                ns.Print(string.format(L["EXPORT_FAILED"], err or "Unknown error"))
                return
            end
            ns.Addon:ShowExportDialog(exportString)
        end,
    })
end

ns.SettingsBuilder.RegisterSection(ns, "Profile", ProfileOptions)
