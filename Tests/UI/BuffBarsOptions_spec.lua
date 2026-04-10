-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("BuffBarsOptions", function()
    local originalGlobals
    local BuffBarsOptions
    local SpellColors
    local SB
    local ns
    local printedMessages

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM_DeepEquals",
            "Settings",
            "CreateSettingsListSectionHeaderInitializer",
            "CreateSettingsButtonInitializer",
            "MinimalSliderWithSteppersMixin",
            "CreateColor",
            "StaticPopupDialogs",
            "StaticPopup_Show",
            "YES",
            "NO",
            "UnitClass",
            "GetSpecialization",
            "GetSpecializationInfo",
            "issecretvalue",
            "issecrettable",
            "canaccessvalue",
            "canaccesstable",
            "time",
            "InCombatLockdown",
            "IsInInstance",
            "IsControlKeyDown",
            "LibStub",
            "CreateFromMixins",
            "SettingsListElementInitializer",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()

        local profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        _G.UnitClass = function()
            return "Demon Hunter", "DEMONHUNTER", 12
        end
        _G.GetSpecialization = function()
            return 2
        end
        _G.GetSpecializationInfo = function()
            return nil, "Havoc"
        end

        _G.issecretvalue = function()
            return false
        end
        _G.issecrettable = function()
            return false
        end
        _G.canaccessvalue = function()
            return true
        end
        _G.canaccesstable = function()
            return true
        end
        _G.time = function()
            return 1000
        end
        _G.InCombatLockdown = function()
            return false
        end
        _G.IsInInstance = function()
            return false
        end
        _G.IsControlKeyDown = function()
            return false
        end

        ns.Constants = {}
        ns.FrameUtil = {
            GetIconTextureFileID = function()
                return nil
            end,
        }
        ns.ScheduleLayoutUpdate = function() end
        ns.ToString = function(v)
            return tostring(v)
        end
        ns.OptionUtil = {
            GetCurrentClassSpec = function()
                return 12, 2, "Demon Hunter", "Havoc", "DEMONHUNTER"
            end,
            IsAnchorModeFree = function()
                return false
            end,
            POSITION_MODE_TEXT = {},
            ApplyPositionModeToBar = function() end,
            IsValueChanged = function()
                return false
            end,
        }

        ns.DebugAssert = function() end
        ns.Log = function() end
        printedMessages = {}
        ns.Print = function(message)
            printedMessages[#printedMessages + 1] = message
        end

        -- Load library
        local lsmw = LibStub("LibLSMSettingsWidgets-1.0", true) or TestHelpers.SetupLibSettingsBuilder()
        lsmw.GetFontValues = function()
            return {}
        end
        lsmw.GetStatusbarValues = function()
            return {}
        end

        -- Load Constants
        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)

        -- Load SpellColors
        ns.Addon = {
            db = {
                profile = { buffBars = {} },
                defaults = { profile = { buffBars = {} } },
            },
            BuffBars = {
                IsEditLocked = function()
                    return false, nil
                end,
                GetActiveSpellData = function()
                    return {}
                end,
            },
            ConfirmReloadUI = function() end,
            ShowConfirmDialog = function() end,
            NewModule = function(_, name)
                return { moduleName = name }
            end,
        }

        TestHelpers.LoadChunk("SpellColors.lua", "Unable to load SpellColors.lua")(nil, ns)
        SpellColors = ns.SpellColors

        -- Load Options (includes SettingsBuilder adapter)
        TestHelpers.LoadChunk("UI/OptionUtil.lua", "Unable to load UI/OptionUtil.lua")(nil, ns)
        TestHelpers.LoadChunk("UI/Options.lua", "Unable to load UI/Options.lua")(nil, ns)

        -- Create root category so subcategory calls work
        SB.CreateRootCategory("Test")

        -- Load BuffBarsOptions
        TestHelpers.LoadChunk("UI/BuffBarsOptions.lua", "Unable to load UI/BuffBarsOptions.lua")(nil, ns)
        BuffBarsOptions = ns.BuffBarsOptions
    end)

    -- _BuildSpellColorRows tests (pure logic, preserved from old tests)

    it("_BuildSpellColorRows deduplicates matching entries and preserves order", function()
        local entries = {
            { key = SpellColors.MakeKey("Active Name", 1001, nil, nil) },
            { key = SpellColors.MakeKey(nil, nil, nil, 2002) },
            { key = SpellColors.MakeKey("Active Name", 1001, 77, 9001) },
            { key = SpellColors.MakeKey("Persisted Only", 3003, nil, nil) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(entries)
        assert.are.equal(3, #rows)
        assert.are.equal("Active Name", rows[1].key.primaryKey)
        assert.are.equal(2002, rows[2].key.primaryKey)
        assert.are.equal("Persisted Only", rows[3].key.primaryKey)
    end)

    it("_BuildSpellColorRows merges matching keys and carries fallback identifiers", function()
        local entries = {
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
            { key = SpellColors.MakeKey(nil, 258920, 77, 9001) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(entries)
        assert.are.equal(1, #rows)
        assert.are.equal("spellName", rows[1].key.keyType)
        assert.are.equal("Immolation Aura", rows[1].key.primaryKey)
        assert.are.equal(258920, rows[1].key.spellID)
        assert.are.equal(77, rows[1].key.cooldownID)
        assert.are.equal(9001, rows[1].key.textureFileID)
        assert.are.equal(9001, rows[1].textureFileID)
    end)

    it("_BuildSpellColorRows does not merge unrelated rows that only share texture", function()
        local entries = {
            { key = SpellColors.MakeKey("Spell A", nil, nil, 1234) },
            { key = SpellColors.MakeKey("Spell B", nil, nil, 1234) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(entries)
        assert.are.equal(2, #rows)
        assert.are.equal("Spell A", rows[1].key.primaryKey)
        assert.are.equal("Spell B", rows[2].key.primaryKey)
    end)

    it("_BuildSpellColorRows merges texture-only keys", function()
        local entries = {
            { key = SpellColors.MakeKey(nil, nil, nil, 4444) },
            { key = SpellColors.MakeKey(nil, nil, nil, 4444) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(entries)
        assert.are.equal(1, #rows)
        assert.are.equal(4444, rows[1].key.primaryKey)
        assert.are.equal(4444, rows[1].textureFileID)
    end)

    it("_BuildSpellColorRows ignores invalid entries and handles nil inputs", function()
        local rows = BuffBarsOptions._BuildSpellColorRows({
            {},
            { key = nil },
            { key = SpellColors.MakeKey("Valid", nil, nil, nil) },
        })

        assert.are.equal(1, #rows)
        assert.are.equal("Valid", rows[1].key.primaryKey)
    end)

    it("section registers with key BuffBars", function()
        -- BuffBarsOptions should have registered itself
        assert.is_function(BuffBarsOptions.RegisterSettings)
    end)

    it("_GetSecretNameFooterState hides the footer when all bar names are available", function()
        local state = BuffBarsOptions._GetSecretNameFooterState({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
        })

        assert.is_false(state.show)
        assert.is_false(state.enabled)
    end)

    it("_GetSecretNameFooterState shows an enabled footer for unlabeled bars outside restricted areas", function()
        local state = BuffBarsOptions._GetSecretNameFooterState({
            { key = { primaryKey = "" } },
        })

        assert.is_true(state.show)
        assert.is_true(state.enabled)
    end)

    it("_GetSecretNameFooterState disables reload in instances", function()
        _G.IsInInstance = function()
            return true, "party"
        end

        local state = BuffBarsOptions._GetSecretNameFooterState({
            { key = { primaryKey = "" } },
        })

        assert.is_true(state.show)
        assert.is_false(state.enabled)
    end)

    it("_GetSecretNameFooterState disables reload during combat", function()
        _G.InCombatLockdown = function()
            return true
        end
        _G.issecretvalue = function(value)
            return value == "Secret Spell"
        end

        local state = BuffBarsOptions._GetSecretNameFooterState({
            { key = { primaryKey = "Secret Spell" } },
        })

        assert.is_true(state.show)
        assert.is_false(state.enabled)
    end)

    it("_BuildSpellColorKeyTooltipLines includes every available key", function()
        local lines = BuffBarsOptions._BuildSpellColorKeyTooltipLines(
            SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001)
        )

        assert.are.same({
            "Spell name: Immolation Aura",
            "Spell ID: 258920",
            "Cooldown ID: 77",
            "Texture File ID: 9001",
        }, lines)
    end)

    it("_HasRowsNeedingReconcile detects rows missing any identifying key", function()
        assert.is_false(BuffBarsOptions._HasRowsNeedingReconcile({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001) },
        }))

        assert.is_true(BuffBarsOptions._HasRowsNeedingReconcile({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
        }))

        assert.is_true(BuffBarsOptions._HasRowsNeedingReconcile({
            { key = SpellColors.MakeKey(nil, 258920, 77, 9001) },
        }))
    end)

    local function registerSpellColorsSpec()
        local spellColorsSpec
        local buttonSpecs = {}
        local refreshCalls = {}
        local originalRegisterFromTable = SB.RegisterFromTable
        local originalButton = SB.Button

        SB.RegisterFromTable = function(tbl)
            if tbl.name == ns.L["SPELL_COLORS_SUBCAT"] then
                spellColorsSpec = tbl
            end
            return originalRegisterFromTable(tbl)
        end
        SB.Button = function(spec)
            buttonSpecs[#buttonSpecs + 1] = spec
            return originalButton(spec)
        end
        SB.RefreshCategory = function(category)
            refreshCalls[#refreshCalls + 1] = category
        end

        BuffBarsOptions.RegisterSettings(SB)

        SB.RegisterFromTable = originalRegisterFromTable
        SB.Button = originalButton

        return assert(spellColorsSpec), refreshCalls, buttonSpecs
    end

    it("does not add the old configure spell colors shortcut to aura bars", function()
        local _, _, buttonSpecs = registerSpellColorsSpec()

        for _, spec in ipairs(buttonSpecs) do
            assert.are_not.equal("Configure Spell Colors", spec.name)
            assert.are_not.equal("Open", spec.buttonText)
        end
    end)

    it("ctrl-hovering a spell color collection row shows all keys for that row", function()
        SpellColors.SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        _G.IsControlKeyDown = function()
            return true
        end

        local spellColorsSpec = registerSpellColorsSpec()
        local item = spellColorsSpec.args.spellColorCollection.items()[2]

        item.onEnter(CreateFrame("Frame"))

        assert.are.equal("Spell color keys", _G.GameTooltip._title)
        assert.are.same({
            "Spell name: Immolation Aura",
            "Spell ID: 258920",
            "Cooldown ID: 77",
            "Texture File ID: 9001",
        }, _G.GameTooltip._lines)
        assert.is_true(_G.GameTooltip._shown)
    end)

    it("puts the default spell color at the top of the collection", function()
        local selectedColor = { r = 0.7, g = 0.6, b = 0.5, a = 1 }
        local scheduledReason

        ns.OptionUtil.OpenColorPicker = function(_, hasOpacity, onChange)
            assert.is_false(hasOpacity)
            onChange(selectedColor)
        end
        ns.Runtime.ScheduleLayoutUpdate = function(_, reason)
            scheduledReason = reason
        end

        local spellColorsSpec, refreshCalls = registerSpellColorsSpec()
        local defaultItem = spellColorsSpec.args.spellColorCollection.items()[1]

        assert.are.equal(ns.L["DEFAULT_COLOR"], defaultItem.label)

        defaultItem.color.onClick()

        assert.are.same(selectedColor, ns.SpellColors.GetDefaultColor())
        assert.are.equal("OptionsChanged", scheduledReason)
        assert.are.same({ ns.L["SPELL_COLORS_SUBCAT"] }, refreshCalls)
    end)

    it("collection defaults reset the default color and custom spell rows", function()
        local scheduledReason

        SpellColors.SetDefaultColor({ r = 0.7, g = 0.6, b = 0.5, a = 1 })
        SpellColors.SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        ns.Runtime.ScheduleLayoutUpdate = function(_, reason)
            scheduledReason = reason
        end

        local spellColorsSpec, refreshCalls = registerSpellColorsSpec()
        spellColorsSpec.args.spellColorCollection.onDefault()

        assert.are.same({}, SpellColors.GetAllColorEntries())
        assert.are.same(ns.Constants.BUFFBARS_DEFAULT_COLOR, SpellColors.GetDefaultColor())
        assert.are.equal("OptionsChanged", scheduledReason)
        assert.are.same({ ns.L["SPELL_COLORS_SUBCAT"] }, refreshCalls)
    end)

    it("header actions disable reconcile and remove stale when every row is complete", function()
        SpellColors.SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })

        local spellColorsSpec = registerSpellColorsSpec()
        local actions = spellColorsSpec.args.spellColorsHeader.actions

        assert.is_false(actions[1].enabled())
        assert.is_false(actions[2].enabled())
    end)

    it("header actions enable reconcile and remove stale for incomplete rows outside restricted areas", function()
        SpellColors.SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, nil, nil), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })

        local spellColorsSpec = registerSpellColorsSpec()
        local actions = spellColorsSpec.args.spellColorsHeader.actions

        assert.is_true(actions[1].enabled())
        assert.is_true(actions[2].enabled())
    end)

    it("header actions disable reconcile and remove stale in restricted areas", function()
        _G.IsInInstance = function()
            return true, "party"
        end
        SpellColors.SetColorByKey(SpellColors.MakeKey(nil, 258920, 77, 9001), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })

        local spellColorsSpec = registerSpellColorsSpec()
        local actions = spellColorsSpec.args.spellColorsHeader.actions

        assert.is_false(actions[1].enabled())
        assert.is_false(actions[2].enabled())
    end)

    it("reconcile action uses ConfirmReloadUI for incomplete rows", function()
        local confirmText

        SpellColors.SetColorByKey(SpellColors.MakeKey(nil, 258920, 77, 9001), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        ns.Addon.ConfirmReloadUI = function(_, text)
            confirmText = text
        end

        local spellColorsSpec = registerSpellColorsSpec()
        spellColorsSpec.args.spellColorsHeader.actions[1].onClick()

        assert.are.equal(ns.L["SPELL_COLORS_SECRET_NAMES_DESC"], confirmText)
    end)

    it("remove stale action exposes the configured tooltip and confirm flow", function()
        local popupKey
        local popupText
        local acceptText
        local cancelText
        local acceptFn
        local scheduledReason

        SpellColors.SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, nil, nil), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        ns.Runtime.ScheduleLayoutUpdate = function(_, reason)
            scheduledReason = reason
        end
        ns.Addon.ShowConfirmDialog = function(_, key, text, button1, button2, onAccept)
            popupKey = key
            popupText = text
            acceptText = button1
            cancelText = button2
            acceptFn = onAccept
        end

        local spellColorsSpec, refreshCalls = registerSpellColorsSpec()
        local removeStaleAction = spellColorsSpec.args.spellColorsHeader.actions[2]

        assert.are.equal(ns.L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"], removeStaleAction.tooltip)

        removeStaleAction.onClick()

        assert.are.equal("ECM_CONFIRM_REMOVE_STALE_SPELL_COLORS", popupKey)
        assert.are.equal(ns.L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"], popupText)
        assert.are.equal(ns.L["REMOVE"], acceptText)
        assert.are.equal(ns.L["SPELL_COLORS_DONT_REMOVE"], cancelText)
        assert.is_function(acceptFn)

        acceptFn()

        assert.are.same({}, ns.SpellColors.GetAllColorEntries())
        assert.are.same({
            ns.L["SPELL_COLORS_REMOVED_STALE_ENTRY"]:format("Immolation Aura"),
        }, printedMessages)
        assert.are.equal("OptionsChanged", scheduledReason)
        assert.are.same({ ns.L["SPELL_COLORS_SUBCAT"] }, refreshCalls)
    end)
end)
