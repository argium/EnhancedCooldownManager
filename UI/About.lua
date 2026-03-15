-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/enhanced-cooldown-manager"
local GITHUB_URL = "https://github.com/argium/EnhancedCooldownManager"

local BUTTON_X = 37 -- matches the settings info-row title anchor
local BUTTON_HEIGHT = 26
local BUTTON_WIDTH = 200

local About = {}

local function createLinksCanvas()
    local frame = CreateFrame("Frame")
    frame:SetHeight(BUTTON_HEIGHT * 2)

    local curseforge = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    curseforge:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    curseforge:SetPoint("TOPLEFT", BUTTON_X, 0)
    curseforge:SetText("CurseForge")
    curseforge:SetScript("OnClick", function()
        ns.Addon:ShowCopyTextDialog(CURSEFORGE_URL, "CurseForge")
    end)

    local github = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    github:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    github:SetPoint("TOPLEFT", BUTTON_X, -BUTTON_HEIGHT)
    github:SetText("GitHub")
    github:SetScript("OnClick", function()
        ns.Addon:ShowCopyTextDialog(GITHUB_URL, "GitHub")
    end)

    frame._curseforge = curseforge
    frame._github = github

    return frame
end

function About.RegisterSettings(SB)
    local version = (C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version") or "Unknown"):gsub("^v", "")
    local authorText = ECM.ColorUtil.Sparkle("Argi")

    local linksCanvas = createLinksCanvas()

    SB.RegisterFromTable({
        name = C.ADDON_NAME,
        rootCategory = true,
        args = {
            author = {
                type = "info",
                name = "Author",
                value = authorText,
                order = 1,
            },
            contributors = {
                type = "info",
                name = "Contributors",
                value = "kayti-wow",
                order = 2,
            },
            version = {
                type = "info",
                name = "Version",
                value = version,
                order = 3,
            },
            linksHeader = {
                type = "description",
                name = "Links",
                order = 9,
            },
            links = {
                type = "canvas",
                canvas = linksCanvas,
                height = BUTTON_HEIGHT * 2,
                order = 10,
            },
        },
    })
end

ns.OptionsSections = ns.OptionsSections or {}
ns.OptionsSections["About"] = About
