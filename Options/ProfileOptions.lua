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

local function CreateProfileDropdown(parent, label, yOffset, getEntries, onSelect)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(400, 30)
    frame:SetPoint("TOPLEFT", 10, yOffset)

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 0, 0)
    text:SetWidth(120)
    text:SetJustifyH("LEFT")
    text:SetText(label)

    local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", text, "RIGHT", 5, 0)
    dropdown:SetWidth(200)

    dropdown:SetupMenu(function(_, rootDescription)
        local entries = getEntries()
        for _, entry in ipairs(entries) do
            rootDescription:CreateButton(entry.label, function()
                onSelect(entry.value)
            end)
        end
    end)

    frame._dropdown = dropdown
    return frame
end

local function CreateProfileCanvas()
    local frame = CreateFrame("Frame", "ECM_ProfileCanvas", UIParent)
    frame:SetSize(600, 400)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText("Profiles")

    local currentLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currentLabel:SetPoint("TOPLEFT", 10, -40)
    currentLabel:SetText("Current Profile:")

    local currentValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    currentValue:SetPoint("LEFT", currentLabel, "RIGHT", 5, 0)

    CreateProfileDropdown(frame, "Switch Profile:", -70,
        function()
            local profiles = mod.db:GetProfiles()
            local entries = {}
            for _, name in ipairs(profiles) do
                entries[#entries + 1] = { label = name, value = name }
            end
            return entries
        end,
        function(name)
            mod.db:SetProfile(name)
            frame:RefreshProfile()
        end
    )

    CreateProfileDropdown(frame, "Copy From:", -105,
        function()
            local profiles = mod.db:GetProfiles()
            local current = mod.db:GetCurrentProfile()
            local entries = {}
            for _, name in ipairs(profiles) do
                if name ~= current then
                    entries[#entries + 1] = { label = name, value = name }
                end
            end
            return entries
        end,
        function(name)
            mod.db:CopyProfile(name)
            frame:RefreshProfile()
        end
    )

    CreateProfileDropdown(frame, "Delete:", -140,
        function()
            local profiles = mod.db:GetProfiles()
            local current = mod.db:GetCurrentProfile()
            local entries = {}
            for _, name in ipairs(profiles) do
                if name ~= current then
                    entries[#entries + 1] = { label = name, value = name }
                end
            end
            return entries
        end,
        function(name)
            local dialog = StaticPopupDialogs["ECM_CONFIRM_DELETE_PROFILE"]
            dialog.text = string.format("Are you sure you want to delete the profile '%s'?", name)
            dialog.OnAccept = function()
                mod.db:DeleteProfile(name)
                frame:RefreshProfile()
            end
            StaticPopup_Show("ECM_CONFIRM_DELETE_PROFILE")
        end
    )

    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 22)
    resetBtn:SetPoint("TOPLEFT", 10, -180)
    resetBtn:SetText("Reset Profile")
    resetBtn:SetScript("OnClick", function()
        StaticPopupDialogs["ECM_CONFIRM_RESET_PROFILE"].OnAccept = function()
            mod.db:ResetProfile()
            frame:RefreshProfile()
        end
        StaticPopup_Show("ECM_CONFIRM_RESET_PROFILE")
    end)

    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetSize(100, 22)
    importBtn:SetPoint("TOPLEFT", 10, -215)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        if InCombatLockdown() then
            mod:Print("Cannot import during combat (reload blocked)")
            return
        end
        mod:ShowImportDialog()
    end)

    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(100, 22)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 10, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local exportString, err = ECM.ImportExport.ExportCurrentProfile()
        if not exportString then
            mod:Print("Export failed: " .. (err or "Unknown error"))
            return
        end
        mod:ShowExportDialog(exportString)
    end)

    function frame:RefreshProfile()
        currentValue:SetText(mod.db:GetCurrentProfile())
    end

    frame:SetScript("OnShow", function(self)
        self:RefreshProfile()
    end)

    return frame
end

local ProfileOptions = {}

function ProfileOptions.RegisterSettings(SB)
    local canvas = CreateProfileCanvas()
    SB.CreateCanvasSubcategory(canvas, "Profiles")
end

ECM.SettingsBuilder.RegisterSection(ns, "Profile", ProfileOptions)
