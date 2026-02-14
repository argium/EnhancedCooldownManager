-- Schema migration for Enhanced Cooldown Manager
-- Handles versioned SavedVariable namespacing and profile migrations (V2 → V8).

local Migration = {}
ECM.Migration = Migration

--- Migration log buffer. Entries are collected during migration and persisted
--- into the new version's SV slot so they survive across sessions.
---@type string[]
local migrationLog = {}

--- Appends a timestamped message to the migration log buffer and sends it to
--- the normal debug log.
---@param message string
local function Log(message)
    migrationLog[#migrationLog + 1] = date("%Y-%m-%d %H:%M:%S") .. "  " .. message
    ECM_log(ECM.Constants.SYS.Migration, nil, message)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Deep copies a table for migration purposes (no depth limit, no secret handling).
--- SavedVariable data is plain Lua tables with primitives and nested tables.
---@param value any
---@param seen table|nil
---@return any
local function DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return nil
    end
    seen[value] = true

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = DeepCopy(v, seen)
    end

    seen[value] = nil
    return copy
end

local function NormalizeLegacyColor(color, defaultAlpha)
    if color == nil then
        return nil
    end

    if type(color) ~= "table" then
        return nil
    end

    if color.r ~= nil or color.g ~= nil or color.b ~= nil then
        return {
            r = color.r or 0,
            g = color.g or 0,
            b = color.b or 0,
            a = color.a or defaultAlpha or 1,
        }
    end

    if color[1] ~= nil then
        return {
            r = color[1],
            g = color[2],
            b = color[3],
            a = color[4] or defaultAlpha or 1,
        }
    end

    return nil
end

--- Returns true when the color matches the expected RGBA values.
---@param color ECM_Color|table|nil
---@param r number
---@param g number
---@param b number
---@param a number|nil
---@return boolean
local function IsColorMatch(color, r, g, b, a)
    if type(color) ~= "table" then
        return false
    end

    local resolved = NormalizeLegacyColor(color, a)
    if not resolved then
        return false
    end

    if resolved.r ~= r or resolved.g ~= g or resolved.b ~= b then
        return false
    end

    if a == nil then
        return true
    end

    return resolved.a == a
end

local function NormalizeColorTable(colorTable, defaultAlpha)
    if type(colorTable) ~= "table" then
        return
    end

    for key, value in pairs(colorTable) do
        colorTable[key] = NormalizeLegacyColor(value, defaultAlpha)
    end
end

local function NormalizeBarConfig(cfg)
    if not cfg then
        return
    end

    cfg.bgColor = NormalizeLegacyColor(cfg.bgColor, 1)
    if cfg.border and cfg.border.color then
        cfg.border.color = NormalizeLegacyColor(cfg.border.color, 1)
    end
    if cfg.colors then
        NormalizeColorTable(cfg.colors, 1)
    end
    if cfg.color then
        cfg.color = NormalizeLegacyColor(cfg.color, 1)
    end
end

local function NormalizeBuffBarsCache(cfg)
    if not (cfg and cfg.colors and type(cfg.colors.cache) == "table") then
        return
    end

    local cache = cfg.colors.cache
    for _, classMap in pairs(cache) do
        if type(classMap) == "table" then
            for _, specMap in pairs(classMap) do
                if type(specMap) == "table" then
                    for index, entry in pairs(specMap) do
                        if type(entry) ~= "table" then
                            specMap[index] = nil
                        else
                            entry.color = nil
                            local spellName = entry.spellName
                            if type(spellName) ~= "string" then
                                specMap[index] = nil
                            else
                                spellName = strtrim(spellName)
                                if spellName == "" or spellName == "Unknown" then
                                    specMap[index] = nil
                                else
                                    entry.spellName = spellName
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Migrates profiles from the per-bar color settings to per-spell.
---@param profile table The profile to migrate
local function MigrateToPerSpellColors(profile)
    local cfg = profile.buffBars
    if not cfg then
        return
    end

    local perBar = cfg.colors.perBar
    local cache = cfg.colors.cache

    if not perBar then
        return
    end

    if not cfg.colors.perSpell then
        cfg.colors.perSpell = {}
    end

    local perSpell = cfg.colors.perSpell

    local function DoSpellMigration(perBar, perSpell, cache)
        for i, v in ipairs(cache) do
            if not v.color and v.spellName then
                local bc = perBar[i]
                if bc then
                    perSpell[v.spellName] = bc
                    cache[i] = {
                        lastSeen = v.lastSeen,
                        spellName = v.spellName,
                    }
                end
            end
        end
    end

    for classID, spec in pairs(perBar) do
        for specID, colors in pairs(spec) do
            if not perSpell[classID] then
                perSpell[classID] = {}
            end
            if not perSpell[classID][specID] then
                perSpell[classID][specID] = {}
            end
            if cache[classID] and cache[classID][specID] then
                DoSpellMigration(perBar[classID][specID], perSpell[classID][specID], cache[classID][specID])
            end
        end
    end

    cfg.colors.perBar = nil
end

--------------------------------------------------------------------------------
-- Schema Migrations
--------------------------------------------------------------------------------

--- Runs all schema migrations on a profile from its current version to CURRENT_SCHEMA_VERSION.
--- Each migration is gated by schemaVersion to ensure it only runs once.
---@param profile table The profile to migrate
function Migration.Run(profile)
    if not profile.schemaVersion then
        return
    end

    local startVersion = profile.schemaVersion
    Log("Starting migration from V" .. startVersion .. " to V" .. ECM.Constants.CURRENT_SCHEMA_VERSION)

    -- Migration: buffBarColors -> buffBars.colors (schema 2 -> 3)
    if profile.schemaVersion < 3 then
        if profile.buffBarColors then
            Log("Migrating buffBarColors to buffBars.colors")

            profile.buffBars = profile.buffBars or {}
            profile.buffBars.colors = profile.buffBars.colors or {}

            local src = profile.buffBarColors
            local dst = profile.buffBars.colors

            dst.perBar = dst.perBar or src.colors or {}
            dst.cache = dst.cache or src.cache or {}
            dst.defaultColor = dst.defaultColor or src.defaultColor
            profile.buffBarColors = nil
        end

        -- Migration: colors.colors -> colors.perBar (rename within buffBars.colors)
        local colorsConfig = profile.buffBars and profile.buffBars.colors
        if colorsConfig and colorsConfig.colors and not colorsConfig.perBar then
            Log("Renaming buffBars.colors.colors to buffBars.colors.perBar")
            colorsConfig.perBar = colorsConfig.colors
            colorsConfig.colors = nil
        end

        Log("Migrated to V3")
        profile.schemaVersion = 3
    end

    if profile.schemaVersion < 4 then
        -- Migration: powerBarTicks.defaultColor -> bold semi-transparent white (schema 3 -> 4)
        local ticksCfg = profile.powerBarTicks
        if ticksCfg and IsColorMatch(ticksCfg.defaultColor, 0, 0, 0, 0.5) then
            ticksCfg.defaultColor = { r = 1, g = 1, b = 1, a = 0.8 }
        end

        -- Migration: demon hunter souls default color update
        local resourceCfg = profile.resourceBar
        local colors = resourceCfg and resourceCfg.colors
        local soulsColor = colors and colors.souls
        if IsColorMatch(soulsColor, 0.46, 0.98, 1.00, nil) then
            colors.souls = { r = 0.259, g = 0.6, b = 0.91, a = 1 }
        end

        -- Migration: powerBarTicks -> powerBar.ticks
        if profile.powerBarTicks then
            profile.powerBar = profile.powerBar or {}
            if not profile.powerBar.ticks then
                profile.powerBar.ticks = profile.powerBarTicks
            end
            profile.powerBarTicks = nil
        end

        -- Normalize stored colors to ECM_Color (legacy conversion happens once here)
        local gbl = profile.global
        if gbl then
            gbl.barBgColor = NormalizeLegacyColor(gbl.barBgColor, 1)
        end

        NormalizeBarConfig(profile.powerBar)
        NormalizeBarConfig(profile.resourceBar)
        NormalizeBarConfig(profile.runeBar)

        local powerBar = profile.powerBar
        if powerBar and powerBar.ticks then
            local tickCfg = powerBar.ticks
            tickCfg.defaultColor = NormalizeLegacyColor(tickCfg.defaultColor, 1)
            if tickCfg.mappings then
                for _, specMap in pairs(tickCfg.mappings) do
                    for _, ticks in pairs(specMap) do
                        for _, tick in ipairs(ticks) do
                            if tick and tick.color then
                                tick.color = NormalizeLegacyColor(tick.color, tickCfg.defaultColor and tickCfg.defaultColor.a or 1)
                            end
                        end
                    end
                end
            end
        end

        local buffBars = profile.buffBars
        if buffBars and buffBars.colors then
            buffBars.colors.defaultColor = NormalizeLegacyColor(buffBars.colors.defaultColor, 1)
            local perBar = buffBars.colors.perBar
            if type(perBar) == "table" then
                for _, specMap in pairs(perBar) do
                    for _, bars in pairs(specMap) do
                        if type(bars) == "table" then
                            for index, color in pairs(bars) do
                                bars[index] = NormalizeLegacyColor(color, 1)
                            end
                        end
                    end
                end
            end
        end

        Log("Migrated to V4")
        profile.schemaVersion = 4
    end

    if profile.schemaVersion < 5 then
        -- Migration: combatFade -> global.outOfCombatFade
        local legacyCombatFade = profile.combatFade
        if legacyCombatFade then
            profile.global = profile.global or {}
            profile.global.outOfCombatFade = profile.global.outOfCombatFade or {}

            local fadeConfig = profile.global.outOfCombatFade
            if legacyCombatFade.enabled ~= nil then
                fadeConfig.enabled = legacyCombatFade.enabled
            end
            if legacyCombatFade.opacity ~= nil then
                fadeConfig.opacity = legacyCombatFade.opacity
            end
            if legacyCombatFade.exceptInInstance ~= nil then
                fadeConfig.exceptInInstance = legacyCombatFade.exceptInInstance
            end
            if legacyCombatFade.exceptIfTargetCanBeAttacked ~= nil then
                fadeConfig.exceptIfTargetCanBeAttacked = legacyCombatFade.exceptIfTargetCanBeAttacked
            end

            profile.combatFade = nil
        end

        Log("Migrated to V5")
        profile.schemaVersion = 5
    end

    if profile.schemaVersion < 6 then
        -- Migration: perBar -> perSpell
        MigrateToPerSpellColors(profile)

        Log("Migrated to V6")
        profile.schemaVersion = 6
    end

    if profile.schemaVersion < 7 then
        -- Migration: normalize buff bar cache entries (remove legacy cache.color and unknown names)
        local buffBars = profile.buffBars
        if buffBars then
            NormalizeBuffBarsCache(buffBars)
        end

        Log("Migrated to V7")
        profile.schemaVersion = 7
    end

    if profile.schemaVersion < 8 then
        -- Migration: split flat perSpell map into separate byName / byTexture tables.
        -- String keys go to byName, number keys go to byTexture.
        -- Each entry is wrapped as { value = color, t = 0 } so that any fresh
        -- write will win during PriorityKeyMap reconciliation.
        local buffBars = profile.buffBars
        if buffBars and type(buffBars.colors) == "table" then
            local colors = buffBars.colors
            local perSpell = colors.perSpell

            if type(perSpell) == "table" then
                if type(colors.byName) ~= "table" then
                    colors.byName = {}
                end
                if type(colors.byTexture) ~= "table" then
                    colors.byTexture = {}
                end

                for classID, specTable in pairs(perSpell) do
                    if type(specTable) == "table" then
                        for specID, entries in pairs(specTable) do
                            if type(entries) == "table" then
                                colors.byName[classID] = colors.byName[classID] or {}
                                colors.byName[classID][specID] = colors.byName[classID][specID] or {}
                                colors.byTexture[classID] = colors.byTexture[classID] or {}
                                colors.byTexture[classID][specID] = colors.byTexture[classID][specID] or {}

                                for key, color in pairs(entries) do
                                    local wrapped = { value = color, t = 0 }
                                    if type(key) == "string" then
                                        colors.byName[classID][specID][key] = wrapped
                                    elseif type(key) == "number" then
                                        colors.byTexture[classID][specID][key] = wrapped
                                    end
                                end
                            end
                        end
                    end
                end

                colors.perSpell = nil
            end

            -- Ensure new key-tier tables exist (lazily populated at runtime
            -- by PriorityKeyMap reconciliation; no data migration needed).
            if type(colors.bySpellID) ~= "table" then
                colors.bySpellID = {}
            end
            if type(colors.byCooldownID) ~= "table" then
                colors.byCooldownID = {}
            end
        end

        Log("Migrated to V8")
        profile.schemaVersion = 8
    end

    Log("Migration complete (V" .. startVersion .. " -> V" .. profile.schemaVersion .. ")")
end

--------------------------------------------------------------------------------
-- Versioned SavedVariable Setup
--------------------------------------------------------------------------------

--- Finds the highest schema version stored in the versions sub-table.
---@param versions table The _versions sub-table.
---@param belowVersion number Only consider versions below this number.
---@return number|nil bestVersion The highest version found, or nil.
local function FindBestPriorVersion(versions, belowVersion)
    local best = nil
    for k in pairs(versions) do
        if type(k) == "number" and k < belowVersion and (not best or k > best) then
            best = k
        end
    end
    return best
end

--- Prepares the versioned SavedVariable store and points a temporary global at
--- the current schema version's data for AceDB to use.
---
--- Structure of SV_NAME (persisted by WoW):
---   {
---     profiles    = {…},          -- legacy AceDB data (untouched by new code)
---     profileKeys = {…},          -- legacy AceDB data (untouched by new code)
---     _versions   = {
---       [7] = {profiles=…, profileKeys=…},
---       [8] = {…},
---     },
---   }
---
--- Old addon versions read the top-level profiles/profileKeys (legacy data).
--- New code reads from _versions[CURRENT_SCHEMA_VERSION] via ACTIVE_SV_KEY.
--- AceDB ignores the _versions key since it only manages known namespace keys.
---
--- Must be called BEFORE AceDB:New().
function Migration.PrepareDatabase()
    local sv = _G[ECM.Constants.SV_NAME] or {}
    _G[ECM.Constants.SV_NAME] = sv

    sv._versions = sv._versions or {}
    local versions = sv._versions
    local version = ECM.Constants.CURRENT_SCHEMA_VERSION

    -- Seed the current version's slot if it doesn't exist yet
    if not versions[version] then
        -- Try the most recent prior version in the store
        local priorVersion = FindBestPriorVersion(versions, version)
        if priorVersion and versions[priorVersion] then
            Log("Copying from schema V" .. priorVersion .. " to V" .. version)
            versions[version] = DeepCopy(versions[priorVersion])
        elseif sv.profiles then
            -- Seed from legacy top-level AceDB data (pre-versioning addon builds)
            local hasProfiles = false
            for _ in pairs(sv.profiles) do
                hasProfiles = true
                break
            end

            if hasProfiles then
                Log("Copying legacy profiles to versioned store V" .. version)
                versions[version] = {
                    profiles = DeepCopy(sv.profiles),
                    profileKeys = sv.profileKeys and DeepCopy(sv.profileKeys) or nil,
                }
            end
        end

        -- Fresh install — empty sub-table, AceDB will populate with defaults
        if not versions[version] then
            versions[version] = {}
        end
    end

    -- Point the temporary global at the current version's sub-table.
    -- AceDB modifies this table in place, so changes are persisted when WoW
    -- serializes SV_NAME on logout.
    rawset(_G, ECM.Constants.ACTIVE_SV_KEY, versions[version])
end

--- Persists collected migration log entries into the current version's SV slot.
--- Should be called after PrepareDatabase + Run are complete.
function Migration.FlushLog()
    if #migrationLog == 0 then
        return
    end

    local sv = _G[ECM.Constants.SV_NAME]
    local versions = sv and sv._versions
    local slot = versions and versions[ECM.Constants.CURRENT_SCHEMA_VERSION]
    if not slot then
        return
    end

    slot._migrationLog = slot._migrationLog or {}
    local dest = slot._migrationLog
    for _, entry in ipairs(migrationLog) do
        dest[#dest + 1] = entry
    end

    wipe(migrationLog)
end
