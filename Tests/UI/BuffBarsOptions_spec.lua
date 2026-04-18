-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("BuffBarsOptions", function()
    local originalGlobals
    local BuffBarsOptions
    local SpellColors
    local BuffSpellColors
    local ExternalSpellColors
    local ns
    local profile
    local defaults
    local printedMessages
    local addonEventCallbacks

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
            "UnitAffectingCombat",
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

        profile, defaults = TestHelpers.MakeOptionsProfile()
        profile.externalBars.enabled = true
        defaults.externalBars.enabled = true
        ns = select(2, TestHelpers.SetupOptionsEnv(profile, defaults))

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
        _G.UnitAffectingCombat = function()
            return false
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
        addonEventCallbacks = {}
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
                profile = profile,
                defaults = { profile = defaults },
            },
            BuffBars = {
                IsEditLocked = function()
                    return false, nil
                end,
                GetActiveSpellData = function()
                    return {}
                end,
            },
            ExternalBars = {
                IsEditLocked = function()
                    return false, nil
                end,
                GetActiveSpellData = function()
                    return {}
                end,
            },
            ConfirmReloadUI = function() end,
            ShowConfirmDialog = function() end,
            RegisterEvent = function(_, event, callback)
                local callbacks = addonEventCallbacks[event] or {}
                callbacks[#callbacks + 1] = callback
                addonEventCallbacks[event] = callbacks
            end,
            UnregisterEvent = function(_, event, callback)
                local callbacks = addonEventCallbacks[event]
                if not callbacks then
                    return
                end

                if callback == nil then
                    addonEventCallbacks[event] = nil
                    return
                end

                for index = #callbacks, 1, -1 do
                    if callbacks[index] == callback then
                        table.remove(callbacks, index)
                    end
                end

                if #callbacks == 0 then
                    addonEventCallbacks[event] = nil
                end
            end,
            NewModule = function(_, name)
                return { moduleName = name }
            end,
        }

        TestHelpers.LoadChunk("SpellColors.lua", "Unable to load SpellColors.lua")(nil, ns)
        SpellColors = ns.SpellColors
        BuffSpellColors = SpellColors.Get(ns.Constants.SCOPE_BUFFBARS)
        ExternalSpellColors = SpellColors.Get(ns.Constants.SCOPE_EXTERNALBARS)

        -- Load Options (includes SettingsBuilder adapter)
        TestHelpers.LoadChunk("UI/OptionUtil.lua", "Unable to load UI/OptionUtil.lua")(nil, ns)
        TestHelpers.LoadChunk("UI/Options.lua", "Unable to load UI/Options.lua")(nil, ns)

        TestHelpers.LoadChunk("UI/SpellColorsPage.lua", "Unable to load UI/SpellColorsPage.lua")(nil, ns)

        -- Load BuffBarsOptions
        TestHelpers.LoadChunk("UI/BuffBarsOptions.lua", "Unable to load UI/BuffBarsOptions.lua")(nil, ns)
        TestHelpers.LoadChunk("UI/ExternalBarsOptions.lua", "Unable to load UI/ExternalBarsOptions.lua")(nil, ns)
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

    it("exports a declarative BuffBars section spec", function()
        assert.are.equal("buffBars", BuffBarsOptions.key)
        assert.are.equal(ns.L["AURA_BARS"], BuffBarsOptions.name)
        assert.are.equal("main", BuffBarsOptions.pages[1].key)
        assert.is_nil(BuffBarsOptions.pages[2])
    end)

    it("_GetSpellColorsPageState hides the secret-name warning when all bar names are available", function()
        local state = BuffBarsOptions._GetSpellColorsPageState({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
        })

        assert.is_false(state.showSecretNameWarning)
        assert.is_true(state.hasRowsNeedingReconcile)
        assert.is_true(state.canReconcile)
        assert.are.equal("", state.warningText)
    end)

    it("_GetSpellColorsPageState shows the secret-name warning for unlabeled bars", function()
        local state = BuffBarsOptions._GetSpellColorsPageState({
            { key = { primaryKey = "" } },
        })

        assert.is_true(state.showSecretNameWarning)
    end)

    it("_GetSpellColorsPageState disables reconcile in instances", function()
        _G.IsInInstance = function()
            return true, "party"
        end

        local state = BuffBarsOptions._GetSpellColorsPageState({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
        })

        assert.is_false(state.canReconcile)
    end)

    it("_GetSpellColorsPageState disables reconcile when the player is in combat", function()
        _G.UnitAffectingCombat = function()
            return true
        end

        local state = BuffBarsOptions._GetSpellColorsPageState({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
        })

        assert.is_false(state.canReconcile)
    end)

    it("_GetSpellColorsPageState disables reconcile during combat lockdown", function()
        _G.InCombatLockdown = function()
            return true
        end

        local state = BuffBarsOptions._GetSpellColorsPageState({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
        })

        assert.is_false(state.canReconcile)
        assert.are.equal(ns.L["SPELL_COLORS_COMBAT_WARNING"], state.warningText)
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

    it("_GetSpellColorsPageState detects rows missing any identifying key", function()
        assert.is_false(BuffBarsOptions._GetSpellColorsPageState({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001) },
        }).hasRowsNeedingReconcile)

        assert.is_true(BuffBarsOptions._GetSpellColorsPageState({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
        }).hasRowsNeedingReconcile)

        assert.is_true(BuffBarsOptions._GetSpellColorsPageState({
            { key = SpellColors.MakeKey(nil, 258920, 77, 9001) },
        }).hasRowsNeedingReconcile)
    end)

    local function registerSpellColorsSpec()
        local spellColorsSpec = assert(ns.SpellColorsPage.CreatePage(ns.L["SPELL_COLORS_SUBCAT"]))
        local refreshCalls = {}
        local fakePage = {
            Refresh = function()
                refreshCalls[#refreshCalls + 1] = spellColorsSpec.name
            end,
        }

        if spellColorsSpec.SetRegisteredPage then
            spellColorsSpec.SetRegisteredPage(fakePage)
        end

        return spellColorsSpec, refreshCalls
    end

    local function getSpellColorsRow(spellColorsSpec, rowID)
        for _, row in ipairs(spellColorsSpec.rows or {}) do
            if row.id == rowID then
                return row
            end
        end

        return nil
    end

    local function getSpellColorCollectionItems(spellColorsSpec, sectionKey)
        local row = assert(getSpellColorsRow(spellColorsSpec, sectionKey .. "SpellColorCollection"))
        return row.items()
    end

    local function getItemLabels(items)
        local labels = {}
        for _, item in ipairs(items or {}) do
            labels[#labels + 1] = item.label
        end
        return labels
    end

    it("does not add the old configure spell colors shortcut to aura bars", function()
        local buttonRows = {}
        for _, row in ipairs(BuffBarsOptions.pages[1].rows) do
            if row.type == "button" then
                buttonRows[#buttonRows + 1] = row
            end
        end

        assert.are.equal(1, #buttonRows)
        assert.are.equal(ns.L["LAYOUT_SUBCATEGORY"], buttonRows[1].name)
        assert.are.equal(ns.L["LAYOUT_PAGE_MOVED_BUTTON_TEXT"], buttonRows[1].buttonText)
    end)

    it("orders the shared spell colors sections with aura bars before external cooldowns", function()
        local spellColorsSpec = registerSpellColorsSpec()
        local rowIDs = {}

        for _, row in ipairs(spellColorsSpec.rows) do
            rowIDs[#rowIDs + 1] = row.id
        end

        assert.same({
            "buffBarsSpellColorsPageActions",
            "spellColorsDescription",
            "buffBarsSpellColorsWarning",
            "buffBarsSpellColorCollection",
            "buffBarsSecretNameDescription",
            "externalBarsSpellColorsPageActions",
            "externalBarsSpellColorsWarning",
            "externalBarsSpellColorCollection",
            "externalBarsSecretNameDescription",
        }, rowIDs)
    end)

    it("keeps a single action set per spell color section", function()
        local spellColorsSpec = registerSpellColorsSpec()
        local actionRowCount = 0

        for _, row in ipairs(spellColorsSpec.rows) do
            if row.type == "pageActions" then
                actionRowCount = actionRowCount + 1
            end
        end

        assert.are.equal(2, actionRowCount)
        assert.is_nil(assert(getSpellColorsRow(spellColorsSpec, "buffBarsSpellColorCollection")).onDefault)
        assert.is_nil(assert(getSpellColorsRow(spellColorsSpec, "externalBarsSpellColorCollection")).onDefault)
    end)

    it("refreshes the registered page on combat enter and leave", function()
        local _, refreshCalls = registerSpellColorsSpec()
        local enterCallbacks = assert(addonEventCallbacks.PLAYER_REGEN_DISABLED)
        local leaveCallbacks = assert(addonEventCallbacks.PLAYER_REGEN_ENABLED)

        assert.are.equal(1, #enterCallbacks)
        assert.are.equal(1, #leaveCallbacks)

        enterCallbacks[1](ns.Addon, "PLAYER_REGEN_DISABLED")
        leaveCallbacks[1](ns.Addon, "PLAYER_REGEN_ENABLED")

        assert.are.same({
            ns.L["SPELL_COLORS_SUBCAT"],
            ns.L["SPELL_COLORS_SUBCAT"],
        }, refreshCalls)
    end)

    it("registers combat refresh callbacks once and refreshes the latest registered page", function()
        local spellColorsSpec = assert(ns.SpellColorsPage.CreatePage(ns.L["SPELL_COLORS_SUBCAT"]))
        local firstRefreshCalls = 0
        local secondRefreshCalls = 0

        spellColorsSpec.SetRegisteredPage({
            Refresh = function()
                firstRefreshCalls = firstRefreshCalls + 1
            end,
        })
        spellColorsSpec.SetRegisteredPage({
            Refresh = function()
                secondRefreshCalls = secondRefreshCalls + 1
            end,
        })

        local enterCallbacks = assert(addonEventCallbacks.PLAYER_REGEN_DISABLED)
        local leaveCallbacks = assert(addonEventCallbacks.PLAYER_REGEN_ENABLED)

        assert.are.equal(1, #enterCallbacks)
        assert.are.equal(1, #leaveCallbacks)

        enterCallbacks[1](ns.Addon, "PLAYER_REGEN_DISABLED")

        assert.are.equal(0, firstRefreshCalls)
        assert.are.equal(1, secondRefreshCalls)
    end)

    it("keeps each section's rows and default colors scoped to its own store", function()
        local buffDefaultColor = { r = 0.2, g = 0.3, b = 0.4, a = 1 }
        local externalDefaultColor = { r = 0.7, g = 0.6, b = 0.5, a = 1 }
        local buffColor = { r = 0.3, g = 0.4, b = 0.5, a = 1 }
        local externalColor = { r = 0.8, g = 0.4, b = 0.2, a = 1 }

        BuffSpellColors:SetDefaultColor(buffDefaultColor)
        ExternalSpellColors:SetDefaultColor(externalDefaultColor)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Buff Scoped", 111, 222, 333), buffColor)
        ExternalSpellColors:SetColorByKey(SpellColors.MakeKey("External Scoped", 444, 555, 666), externalColor)

        local spellColorsSpec = registerSpellColorsSpec()
        local buffItems = getSpellColorCollectionItems(spellColorsSpec, "buffBars")
        local externalItems = getSpellColorCollectionItems(spellColorsSpec, "externalBars")

        assert.same({ ns.L["DEFAULT_COLOR"], "Buff Scoped" }, getItemLabels(buffItems))
        assert.same({ ns.L["DEFAULT_COLOR"], "External Scoped" }, getItemLabels(externalItems))
        assert.are.same(buffDefaultColor, buffItems[1].color.value)
        assert.are.same(externalDefaultColor, externalItems[1].color.value)
        assert.are.same(buffColor, buffItems[2].color.value)
        assert.are.same(externalColor, externalItems[2].color.value)
    end)

    it("routes section swatch writes to the matching scope only", function()
        local buffKey = SpellColors.MakeKey("Buff Scoped", 111, 222, 333)
        local externalKey = SpellColors.MakeKey("External Scoped", 444, 555, 666)
        local buffDefaultColor = { r = 0.2, g = 0.3, b = 0.4, a = 1 }
        local externalDefaultColor = { r = 0.7, g = 0.6, b = 0.5, a = 1 }
        local buffColor = { r = 0.3, g = 0.4, b = 0.5, a = 1 }
        local externalColor = { r = 0.8, g = 0.4, b = 0.2, a = 1 }
        local pickedDefaultColor = { r = 0.9, g = 0.8, b = 0.7, a = 1 }
        local pickedEntryColor = { r = 0.1, g = 0.6, b = 0.9, a = 1 }
        local pickerCalls = 0

        BuffSpellColors:SetDefaultColor(buffDefaultColor)
        ExternalSpellColors:SetDefaultColor(externalDefaultColor)
        BuffSpellColors:SetColorByKey(buffKey, buffColor)
        ExternalSpellColors:SetColorByKey(externalKey, externalColor)

        ns.OptionUtil.OpenColorPicker = function(_, hasOpacity, onChange)
            pickerCalls = pickerCalls + 1
            assert.is_false(hasOpacity)
            onChange(pickerCalls == 1 and pickedDefaultColor or pickedEntryColor)
        end

        local spellColorsSpec = registerSpellColorsSpec()
        local externalItems = getSpellColorCollectionItems(spellColorsSpec, "externalBars")

        externalItems[1].color.onClick()
        externalItems[2].color.onClick()

        assert.are.same(buffDefaultColor, BuffSpellColors:GetDefaultColor())
        assert.are.same(pickedDefaultColor, ExternalSpellColors:GetDefaultColor())
        assert.are.same(buffColor, BuffSpellColors:GetColorByKey(buffKey))
        assert.are.same(pickedEntryColor, ExternalSpellColors:GetColorByKey(externalKey))
    end)

    it("enables reconcile and remove-stale actions per section state", function()
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Buff Incomplete", 258920, nil, nil), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        ExternalSpellColors:SetColorByKey(SpellColors.MakeKey("External Complete", 102342, 77, 9001), {
            r = 0.6, g = 0.5, b = 0.4, a = 1,
        })

        local confirmText
        ns.Addon.ConfirmReloadUI = function(_, text)
            confirmText = text
        end

        local spellColorsSpec = registerSpellColorsSpec()
        local buffActions = assert(getSpellColorsRow(spellColorsSpec, "buffBarsSpellColorsPageActions")).actions
        local externalActions = assert(getSpellColorsRow(spellColorsSpec, "externalBarsSpellColorsPageActions")).actions

        assert.is_true(buffActions[1].enabled())
        assert.is_true(buffActions[2].enabled())
        assert.is_false(externalActions[1].enabled())
        assert.is_false(externalActions[2].enabled())

        buffActions[1].onClick()

        assert.are.equal(ns.L["SPELL_COLORS_SECRET_NAMES_DESC"], confirmText)
    end)

    it("reset action clears only the targeted section", function()
        local buffKey = SpellColors.MakeKey("Buff Keep", 111, 222, 333)
        local externalKey = SpellColors.MakeKey("External Reset", 444, 555, 666)
        local buffDefaultColor = { r = 0.2, g = 0.3, b = 0.4, a = 1 }
        local externalResetDefaultColor = ns.Constants.BUFFBARS_DEFAULT_COLOR
        local externalCustomDefaultColor = { r = 0.9, g = 0.8, b = 0.7, a = 1 }

        BuffSpellColors:SetDefaultColor(buffDefaultColor)
        ExternalSpellColors:SetDefaultColor(externalCustomDefaultColor)
        BuffSpellColors:SetColorByKey(buffKey, { r = 0.3, g = 0.4, b = 0.5, a = 1 })
        ExternalSpellColors:SetColorByKey(externalKey, { r = 0.6, g = 0.5, b = 0.4, a = 1 })

        local spellColorsSpec, refreshCalls = registerSpellColorsSpec()
        local externalActions = assert(getSpellColorsRow(spellColorsSpec, "externalBarsSpellColorsPageActions")).actions

        externalActions[3].onClick()

        assert.are.same(buffDefaultColor, BuffSpellColors:GetDefaultColor())
        assert.are.same(externalResetDefaultColor, ExternalSpellColors:GetDefaultColor())
        assert.are.same({ r = 0.3, g = 0.4, b = 0.5, a = 1 }, BuffSpellColors:GetColorByKey(buffKey))
        assert.is_nil(ExternalSpellColors:GetColorByKey(externalKey))
        assert.are.same({ ns.L["SPELL_COLORS_SUBCAT"] }, refreshCalls)
    end)

    it("remove stale action clears only the targeted section", function()
        local buffKey = SpellColors.MakeKey("Buff Stale", 111, nil, nil)
        local externalKey = SpellColors.MakeKey("External Stale", 444, nil, nil)
        local acceptFn

        BuffSpellColors:SetColorByKey(buffKey, { r = 0.2, g = 0.3, b = 0.4, a = 1 })
        ExternalSpellColors:SetColorByKey(externalKey, { r = 0.6, g = 0.5, b = 0.4, a = 1 })
        ns.Addon.ShowConfirmDialog = function(_, _, _, _, _, onAccept)
            acceptFn = onAccept
        end

        local spellColorsSpec, refreshCalls = registerSpellColorsSpec()
        local externalActions = assert(getSpellColorsRow(spellColorsSpec, "externalBarsSpellColorsPageActions")).actions

        externalActions[2].onClick()
        assert.is_function(acceptFn)

        acceptFn()

        assert.are.same({ r = 0.2, g = 0.3, b = 0.4, a = 1 }, BuffSpellColors:GetColorByKey(buffKey))
        assert.is_nil(ExternalSpellColors:GetColorByKey(externalKey))
        assert.are.same({
            ns.L["SPELL_COLORS_REMOVED_STALE_ENTRY"]:format("External Stale"),
        }, printedMessages)
        assert.are.same({ ns.L["SPELL_COLORS_SUBCAT"] }, refreshCalls)
    end)

    it("greys out a disabled section without affecting the enabled section", function()
        profile.externalBars.enabled = false
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Buff Enabled", 111, 222, 333), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        ExternalSpellColors:SetColorByKey(SpellColors.MakeKey("External Disabled", 444, 555, 666), {
            r = 0.6, g = 0.5, b = 0.4, a = 1,
        })

        local spellColorsSpec = registerSpellColorsSpec()
        local buffHeader = assert(getSpellColorsRow(spellColorsSpec, "buffBarsSpellColorsPageActions"))
        local externalHeader = assert(getSpellColorsRow(spellColorsSpec, "externalBarsSpellColorsPageActions"))
        local buffItems = getSpellColorCollectionItems(spellColorsSpec, "buffBars")
        local externalItems = getSpellColorCollectionItems(spellColorsSpec, "externalBars")

        assert.is_false(buffHeader.disabled())
        assert.is_true(externalHeader.disabled())
        assert.is_true(buffItems[1].color.enabled())
        assert.is_false(externalItems[1].color.enabled())
        assert.are.equal(0.5, externalItems[1].alpha)
        assert.is_true(externalItems[1].iconDesaturated)
        assert.are.equal(0.5, externalItems[2].alpha)
        assert.is_true(externalItems[2].iconDesaturated)
    end)

    it("ctrl-hovering a spell color collection row shows all keys for that row", function()
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        _G.IsControlKeyDown = function()
            return true
        end

        local spellColorsSpec = registerSpellColorsSpec()
        assert.are.equal("pageActions", spellColorsSpec.rows[1].type)
        assert.are.equal("list", spellColorsSpec.rows[4].type)
        assert.are.equal("swatch", spellColorsSpec.rows[4].variant)

        local item = spellColorsSpec.rows[4].items()[2]

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
        local defaultItem = spellColorsSpec.rows[4].items()[1]

        assert.are.equal(ns.L["DEFAULT_COLOR"], defaultItem.label)

        defaultItem.color.onClick()

        assert.are.same(selectedColor, BuffSpellColors:GetDefaultColor())
        assert.are.equal("OptionsChanged", scheduledReason)
        assert.are.same({ ns.L["SPELL_COLORS_SUBCAT"] }, refreshCalls)
    end)

    it("header actions disable reconcile and remove stale when every row is complete", function()
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })

        local spellColorsSpec = registerSpellColorsSpec()
        local actions = spellColorsSpec.rows[1].actions

        assert.is_false(actions[1].enabled())
        assert.is_false(actions[2].enabled())
    end)

    it("header actions enable reconcile and remove stale for incomplete rows outside restricted areas", function()
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, nil, nil), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })

        local spellColorsSpec = registerSpellColorsSpec()
        local actions = spellColorsSpec.rows[1].actions

        assert.is_true(actions[1].enabled())
        assert.is_true(actions[2].enabled())
    end)

    it("header actions disable reconcile and remove stale in restricted areas", function()
        _G.IsInInstance = function()
            return true, "party"
        end
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey(nil, 258920, 77, 9001), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })

        local spellColorsSpec = registerSpellColorsSpec()
        local actions = spellColorsSpec.rows[1].actions

        assert.is_false(actions[1].enabled())
        assert.is_false(actions[2].enabled())
    end)

    it("header actions disable all three actions while spell color editing is locked", function()
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, nil, nil), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        ns.Addon.BuffBars.IsEditLocked = function()
            return true, "combat"
        end

        local spellColorsSpec = registerSpellColorsSpec()
        local actions = spellColorsSpec.rows[1].actions

        assert.is_false(actions[1].enabled())
        assert.is_false(actions[2].enabled())
        assert.is_false(actions[3].enabled())
    end)

    it("reconcile action uses ConfirmReloadUI for incomplete rows", function()
        local confirmText

        BuffSpellColors:SetColorByKey(SpellColors.MakeKey(nil, 258920, 77, 9001), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        ns.Addon.ConfirmReloadUI = function(_, text)
            confirmText = text
        end

        local spellColorsSpec = registerSpellColorsSpec()
        spellColorsSpec.rows[1].actions[1].onClick()

        assert.are.equal(ns.L["SPELL_COLORS_SECRET_NAMES_DESC"], confirmText)
    end)

    it("remove stale action exposes the configured tooltip and confirm flow", function()
        local popupKey
        local popupText
        local acceptText
        local cancelText
        local acceptFn
        local scheduledReason

        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, nil, nil), {
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
        local removeStaleAction = spellColorsSpec.rows[1].actions[2]

        assert.are.equal(ns.L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"], removeStaleAction.tooltip)

        removeStaleAction.onClick()

        assert.are.equal("ECM_CONFIRM_REMOVE_STALE_SPELL_COLORS", popupKey)
        assert.are.equal(ns.L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"], popupText)
        assert.are.equal(ns.L["REMOVE"], acceptText)
        assert.are.equal(ns.L["SPELL_COLORS_DONT_REMOVE"], cancelText)
        assert.is_function(acceptFn)

        acceptFn()

        assert.are.same({}, BuffSpellColors:GetAllColorEntries())
        assert.are.same({
            ns.L["SPELL_COLORS_REMOVED_STALE_ENTRY"]:format("Immolation Aura"),
        }, printedMessages)
        assert.are.equal("OptionsChanged", scheduledReason)
        assert.are.same({ ns.L["SPELL_COLORS_SUBCAT"] }, refreshCalls)
    end)

    it("header action clicks are no-ops while spell color editing is locked", function()
        local confirmText
        local popupKey
        local scheduledReason
        local originalDefaultColor = { r = 0.7, g = 0.6, b = 0.5, a = 1 }

        BuffSpellColors:SetDefaultColor(originalDefaultColor)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, nil, nil), {
            r = 0.2, g = 0.3, b = 0.4, a = 1,
        })
        ns.Addon.BuffBars.IsEditLocked = function()
            return true, "combat"
        end
        ns.Addon.ConfirmReloadUI = function(_, text)
            confirmText = text
        end
        ns.Addon.ShowConfirmDialog = function(_, key)
            popupKey = key
        end
        ns.Runtime.ScheduleLayoutUpdate = function(_, reason)
            scheduledReason = reason
        end

        local spellColorsSpec, refreshCalls = registerSpellColorsSpec()
        local actions = spellColorsSpec.rows[1].actions

        actions[1].onClick()
        actions[2].onClick()
        actions[3].onClick()

        assert.is_nil(confirmText)
        assert.is_nil(popupKey)
        assert.is_nil(scheduledReason)
        assert.are.same(originalDefaultColor, BuffSpellColors:GetDefaultColor())
        assert.are.equal(1, #BuffSpellColors:GetAllColorEntries())
        assert.are.same({}, refreshCalls)
    end)
end)
