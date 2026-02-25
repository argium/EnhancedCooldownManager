-- Schema migration for Enhanced Cooldown Manager
-- Handles versioned SavedVariable namespacing and profile migrations (V2 → V10).

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
    ECM.Log("Migration", message)
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

--- Repairs spell-color metadata and fallback tier links for all class/spec stores.
--- This migration runs once and replaces the previous runtime-only repair path.
---@param profile table The profile to repair
local function RepairSpellColorStores(profile)
    local buffBars = profile.buffBars
    if not (buffBars and type(buffBars.colors) == "table") then
        return
    end

    local colors = buffBars.colors
    if type(colors.byName) ~= "table" then
        colors.byName = {}
    end
    if type(colors.bySpellID) ~= "table" then
        colors.bySpellID = {}
    end
    if type(colors.byCooldownID) ~= "table" then
        colors.byCooldownID = {}
    end
    if type(colors.byTexture) ~= "table" then
        colors.byTexture = {}
    end

    local tierDefs = {
        { storeKey = "byName", keyType = "spellName" },
        { storeKey = "bySpellID", keyType = "spellID", idField = "spellID" },
        { storeKey = "byCooldownID", keyType = "cooldownID", idField = "cooldownID" },
        { storeKey = "byTexture", keyType = "textureFileID", idField = "textureId" },
    }

    -- Normalize metadata per stored tier so options/runtime no longer need to infer.
    for _, tier in ipairs(tierDefs) do
        local store = colors[tier.storeKey]
        for _, classMap in pairs(store) do
            if type(classMap) == "table" then
                for _, specMap in pairs(classMap) do
                    if type(specMap) == "table" then
                        for key, entry in pairs(specMap) do
                            if type(entry) == "table" and type(entry.value) == "table" then
                                local value = entry.value
                                if not value.keyType then
                                    value.keyType = tier.keyType
                                end
                                if tier.idField and type(key) == "number" and value[tier.idField] == nil then
                                    value[tier.idField] = key
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local function EnsureClassSpecStore(store, classID, specID)
        if type(store[classID]) ~= "table" then
            store[classID] = {}
        end
        if type(store[classID][specID]) ~= "table" then
            store[classID][specID] = {}
        end
        return store[classID][specID]
    end

    -- Backfill fallback tiers from byName entries carrying embedded IDs.
    for classID, classMap in pairs(colors.byName) do
        if type(classMap) == "table" then
            for specID, specMap in pairs(classMap) do
                if type(specMap) == "table" then
                    local bySpellIDSpec = EnsureClassSpecStore(colors.bySpellID, classID, specID)
                    local byCooldownIDSpec = EnsureClassSpecStore(colors.byCooldownID, classID, specID)
                    local byTextureSpec = EnsureClassSpecStore(colors.byTexture, classID, specID)

                    for _, entry in pairs(specMap) do
                        if type(entry) == "table" and type(entry.value) == "table" then
                            local value = entry.value

                            if type(value.spellID) == "number" and bySpellIDSpec[value.spellID] == nil then
                                bySpellIDSpec[value.spellID] = entry
                            end
                            if type(value.cooldownID) == "number" and byCooldownIDSpec[value.cooldownID] == nil then
                                byCooldownIDSpec[value.cooldownID] = entry
                            end
                            if type(value.textureId) == "number" and byTextureSpec[value.textureId] == nil then
                                byTextureSpec[value.textureId] = entry
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Normalizes spell-color wrapper metadata and collapses duplicate entries.
--- Stored color payloads become color-only (r/g/b/a); identifiers move to entry.meta.
---@param profile table The profile to repair
local function NormalizeSpellColorStoresV10(profile)
    local stats = {
        skipped = false,
        skipReason = nil,
        tierStoresCreated = {},
        tierStoresCreatedCount = 0,
        classesProcessed = 0,
        specsProcessed = 0,
        entriesScanned = 0,
        validEntries = 0,
        invalidEntries = 0,
        canonicalEntries = 0,
        aliasLinksMerged = 0,
        invalidRetained = 0,
        invalidKeyCollisions = 0,
        entriesMetaNormalized = 0,
        finalEntries = 0,
        perTier = {
            byName = { scanned = 0, invalid = 0, final = 0 },
            bySpellID = { scanned = 0, invalid = 0, final = 0 },
            byCooldownID = { scanned = 0, invalid = 0, final = 0 },
            byTexture = { scanned = 0, invalid = 0, final = 0 },
        },
        anomalySpecs = {},
        anomalySpecsOverflow = 0,
    }

    local buffBars = profile.buffBars
    if not (buffBars and type(buffBars.colors) == "table") then
        stats.skipped = true
        stats.skipReason = "buffBars.colors missing"
        return stats
    end

    local colors = buffBars.colors
    local tierDefs = {
        { storeKey = "byName", keyType = "spellName" },
        { storeKey = "bySpellID", keyType = "spellID" },
        { storeKey = "byCooldownID", keyType = "cooldownID" },
        { storeKey = "byTexture", keyType = "textureFileID" },
    }
    local validKeyTypes = {
        spellName = true,
        spellID = true,
        cooldownID = true,
        textureFileID = true,
    }

    local function ensureTierStore(storeKey)
        if type(colors[storeKey]) ~= "table" then
            colors[storeKey] = {}
            if not stats.tierStoresCreated[storeKey] then
                stats.tierStoresCreated[storeKey] = true
                stats.tierStoresCreatedCount = stats.tierStoresCreatedCount + 1
            end
        end
        return colors[storeKey]
    end

    local function ensureClassSpec(store, classID, specID)
        if type(store[classID]) ~= "table" then
            store[classID] = {}
        end
        if type(store[classID][specID]) ~= "table" then
            store[classID][specID] = {}
        end
        return store[classID][specID]
    end

    local function validKey(k)
        if type(k) == "string" or type(k) == "number" then
            return k
        end
        return nil
    end

    local function validNumericKey(k)
        return type(k) == "number" and k or nil
    end

    local function CountEntries(map)
        if type(map) ~= "table" then
            return 0
        end
        local n = 0
        for _ in pairs(map) do
            n = n + 1
        end
        return n
    end

    local function selectPrimary(spellName, spellID, cooldownID, textureFileID)
        if spellName ~= nil then return spellName, "spellName" end
        if spellID ~= nil then return spellID, "spellID" end
        if cooldownID ~= nil then return cooldownID, "cooldownID" end
        if textureFileID ~= nil then return textureFileID, "textureFileID" end
        return nil, nil
    end

    local function buildKey(spellName, spellID, cooldownID, textureFileID, preferredType)
        local keyType = validKeyTypes[preferredType] and preferredType or nil
        local primaryKey
        if keyType == "spellName" then primaryKey = spellName
        elseif keyType == "spellID" then primaryKey = spellID
        elseif keyType == "cooldownID" then primaryKey = cooldownID
        elseif keyType == "textureFileID" then primaryKey = textureFileID
        end
        if primaryKey == nil then
            primaryKey, keyType = selectPrimary(spellName, spellID, cooldownID, textureFileID)
        end
        if keyType == nil or primaryKey == nil then
            return nil
        end
        return {
            keyType = keyType,
            primaryKey = primaryKey,
            spellName = spellName,
            spellID = spellID,
            cooldownID = cooldownID,
            textureFileID = textureFileID,
        }
    end

    local function keysMatch(a, b)
        if not (a and b) then
            return false
        end
        if a.spellName and b.spellName and a.spellName == b.spellName then return true end
        if a.spellID and b.spellID and a.spellID == b.spellID then return true end
        if a.cooldownID and b.cooldownID and a.cooldownID == b.cooldownID then return true end
        if a.textureFileID and b.textureFileID and a.textureFileID == b.textureFileID then return true end
        return false
    end

    local function mergeKeys(a, b)
        if a == nil then return b end
        if b == nil then return a end
        if not keysMatch(a, b) then return nil end
        return buildKey(
            a.spellName or b.spellName,
            a.spellID or b.spellID,
            a.cooldownID or b.cooldownID,
            a.textureFileID or b.textureFileID,
            nil
        )
    end

    local function entryTs(entry)
        return (type(entry) == "table" and type(entry.t) == "number") and entry.t or 0
    end

    local function scrubValue(value)
        if type(value) ~= "table" then
            return
        end
        value.keyType = nil
        value.primaryKey = nil
        value.spellName = nil
        value.spellID = nil
        value.cooldownID = nil
        value.textureId = nil
        value.textureFileID = nil
        if value.a == nil then
            value.a = 1
        end
    end

    local function buildKeyFromEntry(entry, tierKeyType, rawKey)
        if type(entry) ~= "table" or type(entry.value) ~= "table" then
            return nil
        end

        local value = entry.value
        local meta = type(entry.meta) == "table" and entry.meta or nil
        local spellName = validKey((meta and meta.spellName) or value.spellName)
        local spellID = validNumericKey((meta and meta.spellID) or value.spellID)
        local cooldownID = validNumericKey((meta and meta.cooldownID) or value.cooldownID)
        local textureFileID = validNumericKey(
            (meta and (meta.textureFileID or meta.textureId)) or value.textureFileID or value.textureId
        )
        local preferredType = (meta and meta.keyType) or value.keyType or tierKeyType
        if not validKeyTypes[preferredType] then
            preferredType = tierKeyType
        end

        local vRaw = validKey(rawKey)
        if tierKeyType == "spellName" and type(vRaw) == "string" then
            spellName = vRaw
        elseif tierKeyType == "spellID" and type(vRaw) == "number" then
            spellID = vRaw
        elseif tierKeyType == "cooldownID" and type(vRaw) == "number" then
            cooldownID = vRaw
        elseif tierKeyType == "textureFileID" and type(vRaw) == "number" then
            textureFileID = vRaw
        end

        return buildKey(spellName, spellID, cooldownID, textureFileID, preferredType)
    end

    local function setEntryMeta(entry, key)
        if type(entry) ~= "table" or type(entry.value) ~= "table" or not key then
            return
        end
        scrubValue(entry.value)
        stats.entriesMetaNormalized = stats.entriesMetaNormalized + 1
        entry.meta = {
            keyType = key.keyType,
            primaryKey = key.primaryKey,
            spellName = key.spellName,
            spellID = key.spellID,
            cooldownID = key.cooldownID,
            textureFileID = key.textureFileID,
        }
    end

    for _, tier in ipairs(tierDefs) do
        ensureTierStore(tier.storeKey)
    end

    local classIDs = {}
    for _, tier in ipairs(tierDefs) do
        local store = colors[tier.storeKey]
        for classID, classMap in pairs(store) do
            if type(classMap) == "table" then
                classIDs[classID] = true
            end
        end
    end

    for classID in pairs(classIDs) do
        stats.classesProcessed = stats.classesProcessed + 1
        local specIDs = {}
        for _, tier in ipairs(tierDefs) do
            local classMap = colors[tier.storeKey][classID]
            if type(classMap) == "table" then
                for specID, specMap in pairs(classMap) do
                    if type(specMap) == "table" then
                        specIDs[specID] = true
                    end
                end
            end
        end

        for specID in pairs(specIDs) do
            stats.specsProcessed = stats.specsProcessed + 1
            local groups = {}
            local groupByEntry = {}
            local invalidPerTier = {}
            local newPerTier = {}
            local specScanned = 0
            local specInvalid = 0
            local specInvalidByTier = {}

            for tierIndex, tier in ipairs(tierDefs) do
                invalidPerTier[tierIndex] = {}
                newPerTier[tierIndex] = {}
                specInvalidByTier[tier.storeKey] = 0

                local specStore = ensureClassSpec(colors[tier.storeKey], classID, specID)
                for rawKey, entry in pairs(specStore) do
                    stats.entriesScanned = stats.entriesScanned + 1
                    stats.perTier[tier.storeKey].scanned = stats.perTier[tier.storeKey].scanned + 1
                    specScanned = specScanned + 1
                    local key = buildKeyFromEntry(entry, tier.keyType, rawKey)
                    if not key then
                        invalidPerTier[tierIndex][rawKey] = entry
                        stats.invalidEntries = stats.invalidEntries + 1
                        stats.perTier[tier.storeKey].invalid = stats.perTier[tier.storeKey].invalid + 1
                        specInvalid = specInvalid + 1
                        specInvalidByTier[tier.storeKey] = specInvalidByTier[tier.storeKey] + 1
                    else
                        stats.validEntries = stats.validEntries + 1
                        local groupIndex = groupByEntry[entry]
                        if not groupIndex then
                            for i, group in ipairs(groups) do
                                if keysMatch(group.key, key) then
                                    groupIndex = i
                                    break
                                end
                            end
                        end

                        if not groupIndex then
                            groupIndex = #groups + 1
                            groups[groupIndex] = {
                                key = key,
                                entry = entry,
                                ts = entryTs(entry),
                                tierIndex = tierIndex,
                            }
                        else
                            local group = groups[groupIndex]
                            group.key = mergeKeys(group.key, key) or group.key
                            local t = entryTs(entry)
                            if t > group.ts or (t == group.ts and tierIndex < group.tierIndex) then
                                group.entry = entry
                                group.ts = t
                                group.tierIndex = tierIndex
                            end
                        end

                        if type(entry) == "table" then
                            groupByEntry[entry] = groupIndex
                        end
                    end
                end
            end

            stats.canonicalEntries = stats.canonicalEntries + #groups
            if specScanned > specInvalid and #groups < (specScanned - specInvalid) then
                stats.aliasLinksMerged = stats.aliasLinksMerged + ((specScanned - specInvalid) - #groups)
            end

            for _, group in ipairs(groups) do
                if group.entry and group.key then
                    setEntryMeta(group.entry, group.key)
                    if group.key.spellName ~= nil then
                        newPerTier[1][group.key.spellName] = group.entry
                    end
                    if group.key.spellID ~= nil then
                        newPerTier[2][group.key.spellID] = group.entry
                    end
                    if group.key.cooldownID ~= nil then
                        newPerTier[3][group.key.cooldownID] = group.entry
                    end
                    if group.key.textureFileID ~= nil then
                        newPerTier[4][group.key.textureFileID] = group.entry
                    end
                end
            end

            for tierIndex, tier in ipairs(tierDefs) do
                ensureClassSpec(colors[tier.storeKey], classID, specID)
                colors[tier.storeKey][classID][specID] = newPerTier[tierIndex]
                for rawKey, entry in pairs(invalidPerTier[tierIndex]) do
                    if newPerTier[tierIndex][rawKey] == nil then
                        newPerTier[tierIndex][rawKey] = entry
                        stats.invalidRetained = stats.invalidRetained + 1
                    else
                        stats.invalidKeyCollisions = stats.invalidKeyCollisions + 1
                    end
                end
                for _, entry in pairs(newPerTier[tierIndex]) do
                    if type(entry) == "table" and type(entry.value) == "table" then
                        scrubValue(entry.value)
                    end
                end
                local finalCount = CountEntries(newPerTier[tierIndex])
                stats.finalEntries = stats.finalEntries + finalCount
                stats.perTier[tier.storeKey].final = stats.perTier[tier.storeKey].final + finalCount
            end

            if specInvalid > 0 or (specScanned > specInvalid and #groups < (specScanned - specInvalid)) then
                local invalidTierParts = {}
                for _, tier in ipairs(tierDefs) do
                    local invalidCount = specInvalidByTier[tier.storeKey]
                    if invalidCount and invalidCount > 0 then
                        invalidTierParts[#invalidTierParts + 1] = tier.storeKey .. "=" .. invalidCount
                    end
                end
                local aliasLinks = 0
                if specScanned > specInvalid and #groups < (specScanned - specInvalid) then
                    aliasLinks = (specScanned - specInvalid) - #groups
                end
                local msg = string.format(
                    "class=%s spec=%s scanned=%d valid=%d canonical=%d aliases=%d invalid=%d",
                    tostring(classID),
                    tostring(specID),
                    specScanned,
                    specScanned - specInvalid,
                    #groups,
                    aliasLinks,
                    specInvalid
                )
                if #invalidTierParts > 0 then
                    msg = msg .. " invalidByTier[" .. table.concat(invalidTierParts, ",") .. "]"
                end

                if #stats.anomalySpecs < 20 then
                    stats.anomalySpecs[#stats.anomalySpecs + 1] = msg
                else
                    stats.anomalySpecsOverflow = stats.anomalySpecsOverflow + 1
                end
            end
        end
    end

    return stats
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
        local soulsColor = colors and colors[ECM.Constants.RESOURCEBAR_TYPE_VENGEANCE_SOULS]
        if IsColorMatch(soulsColor, 0.46, 0.98, 1.00, nil) then
            colors[ECM.Constants.RESOURCEBAR_TYPE_VENGEANCE_SOULS] = { r = 0.259, g = 0.6, b = 0.91, a = 1 }
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

    if profile.schemaVersion < 9 then
        -- Migration: repair spell color metadata and fallback tier links.
        RepairSpellColorStores(profile)

        Log("Migrated to V9")
        profile.schemaVersion = 9
    end

    if profile.schemaVersion < 10 then
        -- Migration: normalize spell color wrapper metadata and collapse fragmented entries.
        local v10Stats = NormalizeSpellColorStoresV10(profile)
        if v10Stats and v10Stats.skipped then
            Log("V10 spell color normalization skipped: " .. (v10Stats.skipReason or "unknown reason"))
        elseif v10Stats then
            local createdTiers = {}
            for _, tier in ipairs({ "byName", "bySpellID", "byCooldownID", "byTexture" }) do
                if v10Stats.tierStoresCreated[tier] then
                    createdTiers[#createdTiers + 1] = tier
                end
            end

            Log(string.format(
                "V10 spell color normalization summary: classes=%d specs=%d scanned=%d valid=%d canonical=%d aliases=%d invalid=%d invalidRetained=%d invalidKeyCollisions=%d metaNormalized=%d final=%d",
                v10Stats.classesProcessed,
                v10Stats.specsProcessed,
                v10Stats.entriesScanned,
                v10Stats.validEntries,
                v10Stats.canonicalEntries,
                v10Stats.aliasLinksMerged,
                v10Stats.invalidEntries,
                v10Stats.invalidRetained,
                v10Stats.invalidKeyCollisions,
                v10Stats.entriesMetaNormalized,
                v10Stats.finalEntries
            ))
            Log(string.format(
                "V10 tier breakdown: byName(s=%d i=%d f=%d), bySpellID(s=%d i=%d f=%d), byCooldownID(s=%d i=%d f=%d), byTexture(s=%d i=%d f=%d)",
                v10Stats.perTier.byName.scanned, v10Stats.perTier.byName.invalid, v10Stats.perTier.byName.final,
                v10Stats.perTier.bySpellID.scanned, v10Stats.perTier.bySpellID.invalid, v10Stats.perTier.bySpellID.final,
                v10Stats.perTier.byCooldownID.scanned, v10Stats.perTier.byCooldownID.invalid, v10Stats.perTier.byCooldownID.final,
                v10Stats.perTier.byTexture.scanned, v10Stats.perTier.byTexture.invalid, v10Stats.perTier.byTexture.final
            ))
            if #createdTiers > 0 then
                Log("V10 created missing tier stores: " .. table.concat(createdTiers, ", "))
            end
            for _, msg in ipairs(v10Stats.anomalySpecs) do
                Log("V10 anomaly: " .. msg)
            end
            if v10Stats.anomalySpecsOverflow > 0 then
                Log("V10 anomaly: additional specs omitted=" .. v10Stats.anomalySpecsOverflow)
            end
        end

        Log("Migrated to V10")
        profile.schemaVersion = 10
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
---       [9] = {…},
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

function Migration.PrintLog()
    local sv = _G[ECM.Constants.SV_NAME]
    local versions = sv and sv._versions
    local slot = versions and versions[ECM.Constants.CURRENT_SCHEMA_VERSION]
    if not slot then
        return
    end

    if #slot._migrationLog == 0 then
        print("No migration log entries.")
        return
    end

    print("Schema Migration Log:")
    for _, entry in ipairs(slot._migrationLog) do
        print("- " .. entry)
    end
end
