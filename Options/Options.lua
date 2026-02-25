-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local Options = mod:NewModule("Options")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local C = ECM.Constants

ns.OptionsSections = ns.OptionsSections or {}

local function GetOptionsTable()
    local sections = ns.OptionsSections

    return {
        type = "group",
        name = ColorUtil.Sparkle(C.ADDON_NAME),
        childGroups = "tree",
        args = {
            general = sections.General.GetOptionsTable(),
            powerBar = sections.PowerBar.GetOptionsTable(),
            resourceBar = sections.ResourceBar.GetOptionsTable(),
            runeBar = sections.RuneBar.GetOptionsTable(),
            auraBars = ns.BuffBarsOptions.GetOptionsTable(),
            itemIcons = mod.ItemIconsOptions.GetOptionsTable(),
            profile = sections.Profile.GetOptionsTable(),
            about = sections.About.GetOptionsTable(),
        },
    }
end

function Options:OnInitialize()
    AceConfigRegistry:RegisterOptionsTable("EnhancedCooldownManager", GetOptionsTable)

    self.optionsFrame = AceConfigDialog:AddToBlizOptions(
        "EnhancedCooldownManager",
        "Enhanced Cooldown Manager"
    )

    local db = mod.db
    db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
end

function Options:OnProfileChanged()
    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
end

function Options:OnEnable()
    -- Nothing special needed
end

function Options:OnDisable()
    -- Nothing special needed
end

function Options:OpenOptions()
    if self.optionsFrame then
        Settings.OpenToCategory(self.optionsFrame.name)
    end
end
