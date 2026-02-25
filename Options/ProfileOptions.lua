-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local AceDBOptions = LibStub("AceDBOptions-3.0")
local OB = ECM.OptionBuilder

local ProfileOptions = {}

function ProfileOptions.GetOptionsTable()
    local db = mod.db
    local profileOptions = AceDBOptions:GetOptionsTable(db)
    profileOptions.order = 7

    profileOptions.args = profileOptions.args or {}
    profileOptions.args.importExport = OB.MakeInlineGroup("Import / Export", 0, {
        description = OB.MakeDescription({
            name = "Export your current profile to share or back up. Import will replace all current settings and require a UI reload.\n\n",
            order = 1,
            fontSize = "medium",
        }),
        exportButton = OB.MakeActionButton({
            name = "Export Profile",
            desc = "Export the current profile to a shareable string.",
            order = 2,
            width = "normal",
            func = function()
                local exportString, err = ECM.ImportExport.ExportCurrentProfile()
                if not exportString then
                    mod:Print("Export failed: " .. (err or "Unknown error"))
                    return
                end

                mod:ShowExportDialog(exportString)
            end,
        }),
        importButton = OB.MakeActionButton({
            name = "Import Profile",
            desc = "Import a profile from an export string. This will replace all current settings.",
            order = 3,
            width = "normal",
            func = function()
                if InCombatLockdown() then
                    mod:Print("Cannot import during combat (reload blocked)")
                    return
                end

                mod:ShowImportDialog()
            end,
        }),
    })

    return profileOptions
end

OB.RegisterSection(ns, "Profile", ProfileOptions)
