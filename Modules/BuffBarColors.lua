-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0
--
-- BuffBarColors: Manages per-spell color customization and bar metadata caching
-- for buff bars. This is a stateful singleton — call Init(cfg) before use,
-- and re-call Init() when the profile changes. BuffBars calls RefreshMaps()
-- with scanned bar entries; Options reads the maps and color data directly.

local _, ns = ...

local Util = ns.Util
local C = ns.Constants

---@class ECM_BarCacheEntry
---@field spellName string|nil  Spell name, or nil if secret/unavailable
---@field lastSeen number       GetTime() timestamp of when the bar was last scanned

---@class ECM_BarScanEntry
---@field spellName string|nil
---@field textureFileID number|nil

--------------------------------------------------------------------------------
-- Module Table
--------------------------------------------------------------------------------

local BuffBarColors = {}
ns.BuffBarColors = BuffBarColors

--- Internal config reference, set via Init(). Points to the active buffBars
--- config section. Re-set on profile switch via Init().
---@type table|nil
local _cfg = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Returns current class ID and spec ID, or nil, nil if either is unavailable.
---@return number|nil classID, number|nil specID
local function GetCurrentClassSpec()
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()
    if not classID or not specID then
        return nil, nil
    end
    return classID, specID
end

--- Ensures nested tables exist for buff bar color storage.
---@param cfg table
local function EnsureColorStorage(cfg)
    if not cfg.colors then
        cfg.colors = {
            perSpell = {},
            cache = {},
            defaultColor = C.BUFFBARS_DEFAULT_COLOR,
        }
    end

    local colors = cfg.colors
    if not colors.perSpell then
        colors.perSpell = {}
    end
    if not colors.cache then
        colors.cache = {}
    end
    if not colors.defaultColor then
        colors.defaultColor = C.BUFFBARS_DEFAULT_COLOR
    end
    if not colors.textureMap then
        colors.textureMap = {}
    end
end

--- Returns cfg, classID, specID or nil if any is unavailable.
---@return table|nil cfg, number|nil classID, number|nil specID
local function GetColorContext()
    if not _cfg then
        return nil, nil, nil
    end
    local classID, specID = GetCurrentClassSpec()
    return _cfg, classID, specID
end

--- Compares old/new bar metadata to detect repaint-relevant changes.
---@param oldCache table<number, ECM_BarCacheEntry>|nil
---@param newCache table<number, ECM_BarCacheEntry>
---@param oldTextureMap table<number, number>|nil
---@param newTextureMap table<number, number>
---@return boolean changed True if spell names, texture IDs, or entry count changed
local function HasCacheChanged(oldCache, newCache, oldTextureMap, newTextureMap)
    if not oldCache then
        return true
    end

    -- Check if entry counts differ
    local oldCount, newCount = 0, 0
    for _ in pairs(oldCache) do oldCount = oldCount + 1 end
    for _ in pairs(newCache) do newCount = newCount + 1 end
    if oldCount ~= newCount then
        return true
    end

    -- Compare spell names and texture IDs at each index.
    for index, newEntry in pairs(newCache) do
        local oldEntry = oldCache[index]
        if not oldEntry then
            return true
        end
        if newEntry.spellName ~= oldEntry.spellName then
            return true
        end
        local oldTextureID = oldTextureMap and oldTextureMap[index] or nil
        local newTextureID = newTextureMap and newTextureMap[index] or nil
        if oldTextureID ~= newTextureID then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Initializes (or re-initializes) the color module with a config reference.
--- Must be called before any other method. Called from BuffBars:OnEnable() and
--- again on profile switch when ModuleConfig is rebound.
---@param cfg table The buffBars module config section (self.ModuleConfig)
function BuffBarColors.Init(cfg)
    Util.DebugAssert(cfg ~= nil, "BuffBarColors.Init called with nil config")
    _cfg = cfg
    EnsureColorStorage(_cfg)
end

--- Returns the color lookup key for a bar: spell name if known, or textureFileID fallback.
--- When Blizzard marks spell names as secret (via canaccessvalue), the icon texture file ID
--- serves as a stable identifier for color customization. textureFileID is a number, creating
--- natural key-type separation from string spell names in perSpell storage.
---@param spellName string|nil
---@param textureFileID number|nil
---@return string|number|nil
function BuffBarColors.GetColorKey(spellName, textureFileID)
    if type(spellName) == "string" and not issecretvalue(spellName) then
        return spellName
    end
    if type(textureFileID) == "number" then
        return textureFileID
    end
    return nil
end

--- Returns the per-spell color for the given key and current class/spec, or nil if not set.
---@param colorKey string|number|nil
---@return ECM_Color|nil
function BuffBarColors.LookupSpellColor(colorKey)
    if not _cfg or not _cfg.colors or not _cfg.colors.perSpell then
        Util.DebugAssert(false, "BuffBarColors.LookupSpellColor called before Init or with missing perSpell")
        return C.BUFFBARS_DEFAULT_COLOR
    end

    if type(colorKey) == "string" and issecretvalue(colorKey) then
        -- Secret keys can occur transiently when Blizzard marks aura data as protected.
        -- Treat this as "no custom color" so callers fall back to defaults.
        return nil
    end

    local classID, specID = GetCurrentClassSpec()
    local colors = _cfg.colors.perSpell
    if classID and specID and colors[classID] and colors[classID][specID] then
        local c = colors[classID][specID][colorKey]
        if c then
            return c
        end
    end

    return nil
end

--- Resolves a full color for a bar: per-spell color → default color → constant fallback.
--- Returns r, g, b for direct use in color pickers and SetStatusBarColor.
---@param colorKey string|number|nil
---@return number r, number g, number b
function BuffBarColors.GetSpellColor(colorKey)
    local color = BuffBarColors.LookupSpellColor(colorKey)
        or (_cfg and _cfg.colors and _cfg.colors.defaultColor)
        or C.BUFFBARS_DEFAULT_COLOR
    return color.r, color.g, color.b
end

--- Gets the default bar color as r, g, b components.
---@return number r, number g, number b
function BuffBarColors.GetDefaultColor()
    local c = (_cfg and _cfg.colors and _cfg.colors.defaultColor)
        or C.BUFFBARS_DEFAULT_COLOR
    return c.r, c.g, c.b
end

--- Sets the default bar color.
---@param r number
---@param g number
---@param b number
function BuffBarColors.SetDefaultColor(r, g, b)
    Util.DebugAssert(_cfg and _cfg.colors, "BuffBarColors.SetDefaultColor called before Init")
    if _cfg and _cfg.colors then
        _cfg.colors.defaultColor = { r = r, g = g, b = b, a = 1 }
    end
end

--- Sets a custom color for the given spell/texture key for current class/spec.
---@param colorKey string|number
---@param r number
---@param g number
---@param b number
---@return boolean changed True if the color was actually set
function BuffBarColors.SetSpellColor(colorKey, r, g, b)
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return false
    end

    local colors = cfg.colors.perSpell
    colors[classID] = colors[classID] or {}
    colors[classID][specID] = colors[classID][specID] or {}
    colors[classID][specID][colorKey] = { r = r, g = g, b = b, a = 1 }

    Util.Log("BuffBarColors", "SetSpellColor", { colorKey = colorKey, r = r, g = g, b = b })
    return true
end

--- Removes the custom color for the given spell/texture key for current class/spec.
---@param colorKey string|number
---@return boolean changed True if a color was actually removed
function BuffBarColors.ResetSpellColor(colorKey)
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return false
    end

    local colors = cfg.colors.perSpell
    if not (colors[classID] and colors[classID][specID]) then
        return false
    end

    local hadColor = colors[classID][specID][colorKey] ~= nil
    colors[classID][specID][colorKey] = nil

    Util.Log("BuffBarColors", "ResetSpellColor", { colorKey = colorKey })
    return hadColor
end

--- Checks if the given spell/texture key has a custom color set for current class/spec.
---@param colorKey string|number
---@return boolean
function BuffBarColors.HasCustomSpellColor(colorKey)
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return false
    end

    local spells = cfg.colors.perSpell
    return spells[classID] and spells[classID][specID] and spells[classID][specID][colorKey] ~= nil
end

--- Gets cached bar entries for current class/spec (for Options UI).
---@return table<number, ECM_BarCacheEntry> cache Indexed by bar position
function BuffBarColors.GetBarCache()
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return {}
    end

    local cache = cfg.colors.cache
    if cache[classID] and cache[classID][specID] then
        return cache[classID][specID]
    end

    return {}
end

--- Gets cached texture file IDs for current class/spec (for Options UI).
--- Stored separately from cache entries to avoid taint propagation.
---@return table<number, number> textures Indexed by bar position, values are texture file IDs
function BuffBarColors.GetBarTextureMap()
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return {}
    end

    local textureMap = cfg.colors.textureMap
    if textureMap and textureMap[classID] and textureMap[classID][specID] then
        return textureMap[classID][specID]
    end

    return {}
end

--- Gets configured per-spell colors for current class/spec (for Options UI).
---@return table<string|number, ECM_Color> perSpell Indexed by spell name or texture file ID
function BuffBarColors.GetPerSpellColors()
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return {}
    end

    local perSpell = cfg.colors.perSpell
    if perSpell[classID] and perSpell[classID][specID] then
        return perSpell[classID][specID]
    end

    return {}
end

--- Refreshes bar metadata cache and texture map from scanned bar entries.
--- Accepts an array of {spellName, textureFileID} tuples produced by BuffBars
--- after scanning the viewer's children. Handles secret-name resolution and
--- textureID→spellName color migration.
---
--- TODO: Orphaned color cleanup — colors for removed/unobtainable spells persist
--- indefinitely in perSpell storage. Cleaning requires comparing perSpell keys
--- against the cache, risking deletion of colors for temporarily-unequipped buffs.
---@param scanEntries ECM_BarScanEntry[] Array of scanned bar data
---@return boolean changed True if cache contents changed or color migration occurred
function BuffBarColors.RefreshMaps(scanEntries)
    if not _cfg then
        Util.DebugAssert(false, "BuffBarColors.RefreshMaps called before Init")
        return false
    end

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return false
    end

    if not scanEntries or #scanEntries == 0 then
        Util.Log("BuffBarColors", "RefreshMaps - no scan entries.", {
            classID = classID,
            specID = specID,
        })
        return false
    end

    -- Build the new cache and texture maps from scan entries
    local nextBarIndexToSpellNameMap = {}
    local nextBarIndexToTextureIdMap = {}
    for index, entry in ipairs(scanEntries) do
        local spellName = nil
        local textureFileID = nil

        if issecrettable(entry) then
            Util.Log("BuffBarColors", "RefreshMaps", {
                message = "scan entry table is secret, skipping values",
            })
        else
            local rawSpellName = type(entry) == "table" and entry.spellName or nil
            if type(rawSpellName) == "string" and not issecretvalue(rawSpellName) then
                rawSpellName = strtrim(rawSpellName)
                if rawSpellName ~= "" then
                    spellName = rawSpellName
                end
            end

            local rawTextureID = type(entry) == "table" and entry.textureFileID or nil
            if type(rawTextureID) == "number" and not issecretvalue(rawTextureID) then
                textureFileID = rawTextureID
            end
        end

        nextBarIndexToSpellNameMap[index] = {
            spellName = spellName,
            lastSeen = GetTime(),
        }
        nextBarIndexToTextureIdMap[index] = textureFileID
    end

    local barIndexToSpellNameMap = _cfg.colors.cache
    barIndexToSpellNameMap[classID] = barIndexToSpellNameMap[classID] or {}

    local barIndexToTextureIdMap = _cfg.colors.textureMap
    barIndexToTextureIdMap[classID] = barIndexToTextureIdMap[classID] or {}

    -- Texture file ID resolution and color migration:
    -- textureFileIDs are stored in a separate table (textureMap) from cache entries
    -- to prevent taint propagation from secret spell names to texture IDs.
    -- 1. Build textureFileID → spellName mapping from old textureMap + old cache
    -- 2. Resolve nil spellNames in new cache via textureFileID lookup
    -- 3. Migrate perSpell colors from textureFileID (number) key to resolved spell name
    local spellNameMapExists = barIndexToSpellNameMap[classID][specID]
    local textureIdMapExists = barIndexToTextureIdMap[classID] and barIndexToTextureIdMap[classID][specID]
    local didMigrateColor = false
    if spellNameMapExists and textureIdMapExists then
        local texIdToName = {}
        for index, entry in pairs(spellNameMapExists) do
            local texId = textureIdMapExists[index]
            if entry.spellName and texId and not issecretvalue(texId) and not issecretvalue(entry.spellName) then
                texIdToName[texId] = entry.spellName
            end
        end

        local perSpell = _cfg.colors.perSpell
        local classSpells = perSpell and perSpell[classID]
        local specSpells = classSpells and classSpells[specID]

        for index, newEntry in pairs(nextBarIndexToSpellNameMap) do
            local newTexId = nextBarIndexToTextureIdMap[index]
            if not newEntry.spellName and newTexId and not issecretvalue(newTexId) then
                local resolvedName = texIdToName[newTexId]
                if resolvedName and not issecretvalue(resolvedName) then
                    Util.Log("BuffBarColors", "RefreshMaps - resolved spell name", {
                        resolvedName = resolvedName,
                        textureFileID = newTexId,
                    })
                    newEntry.spellName = resolvedName
                end
            end

            -- Migrate colors from textureFileID key to real spell name
            if specSpells and newEntry.spellName and newTexId and not issecretvalue(newTexId) then
                if specSpells[newTexId] then
                    if specSpells[newEntry.spellName] == nil then
                        Util.Log("BuffBarColors", "RefreshMaps - migrating color from texture ID to spell name", {
                            spellName = newEntry.spellName,
                            textureFileID = newTexId,
                        })
                        specSpells[newEntry.spellName] = specSpells[newTexId]
                    end
                    didMigrateColor = true
                end
                specSpells[newTexId] = nil
            end
        end
    end

    -- Detect whether anything actually changed before overwriting
    local oldCache = barIndexToSpellNameMap[classID][specID]
    local oldTextureMap = barIndexToTextureIdMap[classID] and barIndexToTextureIdMap[classID][specID]
    local changed = HasCacheChanged(oldCache, nextBarIndexToSpellNameMap, oldTextureMap, nextBarIndexToTextureIdMap)

    barIndexToSpellNameMap[classID][specID] = nextBarIndexToSpellNameMap
    barIndexToTextureIdMap[classID][specID] = nextBarIndexToTextureIdMap

    if changed or didMigrateColor then
        Util.Log("BuffBarColors", "RefreshMaps - cache updated")
    end

    return changed or didMigrateColor
end
