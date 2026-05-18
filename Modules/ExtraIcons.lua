-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local BarMixin = ns.BarMixin
local FrameUtil = ns.FrameUtil
local ExtraIcons = ns.Addon:NewModule("ExtraIcons")
ns.Addon.ExtraIcons = ExtraIcons

-- ExtraIcons adds the user's chosen potions, trinkets, racials, and spells
-- directly after Blizzard's cooldown viewer rows. Think of each Blizzard row
-- as a train: this module adds a small extra car to the end without moving the
-- train station anchor that other ECM modules use.
local BUILTIN_STACKS = ns.Constants.BUILTIN_STACKS
local RACIAL_ABILITIES = ns.Constants.RACIAL_ABILITIES
local DEFAULT_SIZE = ns.Constants.DEFAULT_EXTRA_ICON_SIZE
local MAIN_BORDER_SCALE = ns.Constants.EXTRA_ICON_MAIN_BORDER_SCALE
local UTILITY_BORDER_SCALE = ns.Constants.EXTRA_ICON_UTILITY_BORDER_SCALE
local canAccessTable = _G.canaccesstable

-- Some racial abilities have different spell IDs for different races/factions.
-- This lookup lets a saved spell ID find its whole family of equivalent IDs.
local RACIAL_SPELL_ALIASES = {}
for _, racial in pairs(RACIAL_ABILITIES) do
    local spellIds = racial.spellIds or { racial.spellId }
    for _, spellId in ipairs(spellIds) do
        RACIAL_SPELL_ALIASES[spellId] = spellIds
    end
end

-- Ordered viewer keys mapped to their Blizzard frame globals. The order matters
-- because the main and utility rows may need to move together as one visual
-- group when extra icons widen one row.
local VIEWERS = {
    { key = "main", blizzKey = "EssentialCooldownViewer", borderScale = { MAIN_BORDER_SCALE, MAIN_BORDER_SCALE }, ownsAnchor = true },
    -- Utility icon frames render square; keep the overlay square so extras do not look short.
    { key = "utility", blizzKey = "UtilityCooldownViewer", borderScale = { UTILITY_BORDER_SCALE, UTILITY_BORDER_SCALE } },
}
local BLIZZ_KEY = {}
for _, v in ipairs(VIEWERS) do BLIZZ_KEY[v.key] = v.blizzKey end

--------------------------------------------------------------------------------
-- Shared horizontal centering
--------------------------------------------------------------------------------

local function cachePoint(vs, blizzFrame)
    -- Save the Blizzard viewer's first anchor before ECM moves it. Future
    -- layouts always start from this remembered "home" position so small
    -- refreshes do not keep adding offsets on top of old offsets.
    if vs.originalPoint or not blizzFrame then return end
    local point, relativeTo, relativePoint, x, y = blizzFrame:GetPoint()
    vs.originalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
end

local function applyPoint(vs, blizzFrame, offsetX)
    -- Move the Blizzard viewer relative to its saved home position. The shared
    -- FrameUtil helper does nothing when the anchor is already correct, which
    -- prevents unnecessary clear/re-anchor work and visual flicker.
    local p = vs and vs.originalPoint
    if not p or not blizzFrame then return end
    FrameUtil.LazySetAnchors(blizzFrame, { { p[1], p[2], p[3], p[4] + (offsetX or 0), p[5] } })
end

local function horizontalBounds(point, width)
    -- Convert an anchor name into "how far this frame reaches left and right
    -- from its anchor." A left-anchored frame grows to the right, a right
    -- anchored frame grows to the left, and a centered frame grows both ways.
    if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then
        return 0, width
    elseif point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
        return -width, 0
    end
    local h = width / 2
    return -h, h
end

local function getFrameDebugName(frame)
    if not frame then return nil end
    local name = frame.GetName and frame:GetName()
    return name or tostring(frame)
end

local function getPointDebugData(point)
    if not point then return nil end
    return {
        point = point[1],
        relativeTo = getFrameDebugName(point[2]),
        relativePoint = point[3],
        x = point[4],
        y = point[5],
    }
end

local function logSharedOffsets(why, reason, mainFrame, utilFrame, mainPoint, utilPoint, offsets)
    if not ns.IsDebugEnabled() then return end
    ns.Log("ExtraIcons", "Shared offsets: " .. reason, {
        reason = why,
        main = {
            shown = mainFrame and mainFrame:IsShown(),
            width = mainFrame and mainFrame:GetWidth(),
            point = getPointDebugData(mainPoint),
            offset = offsets.main,
        },
        utility = {
            shown = utilFrame and utilFrame:IsShown(),
            width = utilFrame and utilFrame:GetWidth(),
            point = getPointDebugData(utilPoint),
            offset = offsets.utility,
        },
    })
end

--- Computes a per-viewer horizontal offset that re-centers both viewers as a
--- single stacked group when they share the same original anchor.
--- ELI5: if two rows are stacked on the same nail, and one row becomes wider,
--- nudge each row so the whole stack still looks centered on that nail.
local function getSharedOffsets(viewers, why)
    local offsets = { main = 0, utility = 0 }
    local mainState, utilState = viewers.main, viewers.utility
    if not mainState or not utilState then
        logSharedOffsets(why, "missing viewer state", nil, nil, nil, nil, offsets)
        return offsets
    end

    local mainFrame = _G[BLIZZ_KEY.main]
    local utilFrame = _G[BLIZZ_KEY.utility]
    cachePoint(mainState, mainFrame)
    cachePoint(utilState, utilFrame)

    local mp, up = mainState.originalPoint, utilState.originalPoint
    if not mp or not up then
        logSharedOffsets(why, "missing original point", mainFrame, utilFrame, mp, up, offsets)
        return offsets
    end
    if mainFrame and up[2] == mainFrame then
        logSharedOffsets(why, "utility anchored to main", mainFrame, utilFrame, mp, up, offsets)
        return offsets
    end
    if up[1] ~= mp[1] or up[2] ~= mp[2] or up[3] ~= mp[3] or up[4] ~= mp[4] then
        logSharedOffsets(why, "independent anchors", mainFrame, utilFrame, mp, up, offsets)
        return offsets
    end

    local sharedLeft, sharedRight
    for _, v in ipairs(VIEWERS) do
        local frame = _G[v.blizzKey]
        local p = viewers[v.key].originalPoint
        if frame and frame:IsShown() and p then
            local l, r = horizontalBounds(p[1], frame:GetWidth() or 0)
            sharedLeft = sharedLeft and math.min(sharedLeft, l) or l
            sharedRight = sharedRight and math.max(sharedRight, r) or r
        end
    end
    if not sharedLeft then
        logSharedOffsets(why, "no shown viewers", mainFrame, utilFrame, mp, up, offsets)
        return offsets
    end
    local center = (sharedLeft + sharedRight) / 2

    for _, v in ipairs(VIEWERS) do
        local frame = _G[v.blizzKey]
        local p = viewers[v.key].originalPoint
        if frame and frame:IsShown() and p then
            local l, r = horizontalBounds(p[1], frame:GetWidth() or 0)
            offsets[v.key] = center - ((l + r) / 2)
        end
    end
    logSharedOffsets(why, "computed", mainFrame, utilFrame, mp, up, offsets)
    return offsets
end

local function updateMainViewerAnchor(vs, blizzFrame, rightFrame)
    -- Chained ECM modules ask this module where the main row ends. This hidden
    -- anchor stretches from Blizzard's main viewer to the extra-icon container,
    -- so the next module attaches after the combined width instead of only
    -- after Blizzard's original icons.
    local anchor = vs and vs.anchorFrame
    if not anchor then return end

    if not blizzFrame or not blizzFrame:IsShown() then
        anchor:Hide()
        return
    end

    local right = rightFrame and rightFrame:IsShown() and rightFrame or blizzFrame
    anchor:ClearAllPoints()
    anchor:SetPoint("LEFT", blizzFrame, "LEFT", 0, 0)
    anchor:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    anchor:SetPoint("TOP", blizzFrame, "TOP", 0, 0)
    anchor:SetPoint("BOTTOM", blizzFrame, "BOTTOM", 0, 0)
    anchor:Show()
end

--------------------------------------------------------------------------------
-- Entry resolution
--------------------------------------------------------------------------------

local function resolveEquipSlot(slotId)
    -- Equipment entries track a gear slot, not a fixed item. Resolve the item
    -- currently worn in that slot so swapping trinkets updates the extra icon.
    local itemId = GetInventoryItemID("player", slotId)
    if not itemId then return nil end
    local _, spellId = C_Item.GetItemSpell(itemId)
    if not spellId then return nil end
    local texture = GetInventoryItemTexture("player", slotId)
    if not texture then return nil end
    return { itemId = itemId, texture = texture, slotId = slotId }
end

local function resolveItem(ids, showIfMissing)
    -- Item entries can list several item IDs in priority order. Use the first
    -- owned item with an icon; optionally show a grey missing icon for the first
    -- configured item if none are owned.
    local missingData

    for _, entry in ipairs(ids) do
        local itemId = entry.itemID or entry.itemId
        if itemId and C_Item.GetItemCount(itemId) > 0 then
            local texture = C_Item.GetItemIconByID(itemId)
            if texture then return { itemId = itemId, texture = texture } end
        elseif itemId and showIfMissing and not missingData then
            local texture = C_Item.GetItemIconByID(itemId)
            if texture then missingData = { itemId = itemId, texture = texture, missing = true } end
        end
    end

    return missingData
end

local function resolveKnownSpell(spellId)
    -- A spell is usable only if the current character knows it and Blizzard can
    -- provide an icon for it.
    if spellId and C_SpellBook.IsSpellKnown(spellId) then
        local texture = C_Spell.GetSpellTexture(spellId)
        if texture then return { spellId = spellId, texture = texture } end
    end
end

local function resolveSpell(ids)
    -- Spell entries also use priority order. Racial spells may resolve through
    -- aliases because the configured spell may have a race-specific equivalent.
    for _, entry in ipairs(ids) do
        local spellId = type(entry) == "table" and entry.spellId or entry
        local data = resolveKnownSpell(spellId)
        if data then return data end

        local aliases = RACIAL_SPELL_ALIASES[spellId]
        if aliases then
            for _, aliasSpellId in ipairs(aliases) do
                if aliasSpellId ~= spellId then
                    data = resolveKnownSpell(aliasSpellId)
                    if data then return data end
                end
            end
        end
    end
end

local function isNonPvpInstance()
    -- "Non-PvP instance" means dungeons, raids, scenarios, and similar places
    -- where potion rules may differ from battlegrounds and arenas.
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType ~= "pvp" and instanceType ~= "arena"
end

local function shouldSuppressItemStack(itemStack)
    -- Some built-in item groups intentionally disappear in rated PvP or
    -- non-PvP instances so the row only shows context-relevant consumables.
    if not itemStack then return true end
    if itemStack.hideInRatedPvp and C_PvP.IsRatedMap() then return true end
    if itemStack.hideInInstances and isNonPvpInstance() then return true end
    return false
end

local function resolveItemStack(entry, moduleConfig)
    -- Custom item stacks are user-configured groups such as "my preferred
    -- health potions." Resolve the stack's item list like a normal item entry.
    local itemStacks = moduleConfig and moduleConfig.itemStacks
    local itemStack = itemStacks and itemStacks.byId and itemStacks.byId[entry.itemStackId]
    return not shouldSuppressItemStack(itemStack)
        and itemStack.ids
        and resolveItem(itemStack.ids, itemStack.showIfMissing == true)
        or nil
end

local function resolveEntry(entry, moduleConfig)
    -- Turn one saved config entry into one drawable icon, or nil if it should
    -- not be shown right now. Built-in stack keys expand into their real entry
    -- data before the normal kind-specific resolver runs.
    local kind, slotId, ids
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then return nil end
        kind, slotId, ids = stack.kind, stack.slotId, stack.ids
    else
        kind, slotId, ids = entry.kind, entry.slotId, entry.ids
    end
    if kind == "equipSlot" then return resolveEquipSlot(slotId) end
    if kind == "item" then return ids and resolveItem(ids) end
    if kind == "itemStack" then return resolveItemStack(entry, moduleConfig) end
    if kind == "spell" then return ids and resolveSpell(ids) end
end

local _resolved = {}
local function resolveEntries(entries, moduleConfig)
    -- Reuse one temporary result table on every layout pass to avoid allocating
    -- a new table during frequent UI refreshes.
    wipe(_resolved)
    for _, entry in ipairs(entries) do
        local data = not entry.disabled and resolveEntry(entry, moduleConfig) or nil
        if data then _resolved[#_resolved + 1] = data end
    end
    return _resolved
end

--------------------------------------------------------------------------------
-- Icon creation and cooldown
--------------------------------------------------------------------------------

local function createIcon(parent, size, borderScale)
    -- Build one square extra icon using Blizzard-like parts: artwork, mask,
    -- cooldown swipe, border, count text, and optional shadow. The caller
    -- reuses these icons from a pool instead of creating new ones every layout.
    local icon = CreateFrame("Button", nil, parent)
    icon:SetSize(size, size)

    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetPoint("CENTER")
    icon.Icon:SetSize(size, size)

    icon.Mask = icon:CreateMaskTexture()
    icon.Mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
    icon.Mask:SetPoint("CENTER")
    icon.Mask:SetSize(size, size)
    icon.Icon:AddMaskTexture(icon.Mask)

    icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints()
    icon.Cooldown:SetDrawEdge(true)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetHideCountdownNumbers(false)
    icon.Cooldown:SetSwipeTexture([[Interface\HUD\UI-HUD-CoolDownManager-Icon-Swipe]], 0, 0, 0, 0.2)
    icon.Cooldown:SetEdgeTexture([[Interface\Cooldown\UI-HUD-ActionBar-SecondaryCooldown]])

    icon.Border = icon:CreateTexture(nil, "OVERLAY")
    icon.Border:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
    icon.Border:SetPoint("CENTER")
    icon.Border:SetSize(size * borderScale[1], size * borderScale[2])

    icon.Count = icon:CreateFontString(nil, "OVERLAY")
    icon.Count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    icon.Count:SetJustifyH("RIGHT")
    icon.Count:SetJustifyV("BOTTOM")
    icon.Count:Hide()

    icon.Shadow = icon:CreateTexture(nil, "OVERLAY")
    icon.Shadow:SetAtlas("UI-CooldownManager-OORshadow")
    icon.Shadow:SetAllPoints()
    icon.Shadow:Hide()

    return icon
end

local function updateIconCooldown(icon)
    -- Pick the right Blizzard cooldown API for the thing shown on this icon:
    -- spells use spell cooldowns, equipment slots use inventory cooldowns, and
    -- bag items use item cooldowns.
    if icon.spellId then
        local cdInfo = C_Spell.GetSpellCooldown(icon.spellId)
        if cdInfo and cdInfo.isOnGCD then
            icon.Cooldown:SetCooldown(0, 0)
            return
        end
        -- Charge spells: per-charge timer so the icon shows ready while
        -- charges remain. Single-charge spells report zero-span here.
        local charges = C_Spell.GetSpellCharges(icon.spellId)
        local isCharge = charges and charges.maxCharges and charges.maxCharges > 1
        local durObj = isCharge
            and C_Spell.GetSpellChargeDuration(icon.spellId)
            or C_Spell.GetSpellCooldownDuration(icon.spellId)
        if durObj then
            icon.Cooldown:SetCooldown(0, 0)
            icon.Cooldown:SetCooldownFromDurationObject(durObj)
        else
            icon.Cooldown:Clear()
        end
    elseif icon.slotId then
        local start, duration, enable = GetInventoryItemCooldown("player", icon.slotId)
        if enable == 1 and duration > 0 then
            icon.Cooldown:SetCooldown(start, duration)
        else
            icon.Cooldown:Clear()
        end
    elseif icon.itemId then
        local start, duration, enable = C_Item.GetItemCooldown(icon.itemId)
        if enable and duration > 0 then
            icon.Cooldown:SetCooldown(start, duration)
        else
            icon.Cooldown:Clear()
        end
    end
end

local function setIconCountText(icon, text)
    -- Count text is optional. Nil means "hide the number"; any value means
    -- "show this number on top of the icon."
    if text ~= nil then
        icon.Count:SetText(tostring(text))
        icon.Count:Show()
    else
        icon.Count:SetText(nil)
        icon.Count:Hide()
    end
end

local function updateIconCountText(icon, globalConfig, config)
    -- Item icons can show stack counts and spell icons can show charges. Only
    -- show useful numbers: one item or a non-charge spell should stay clean.
    if not icon.Count then return end
    FrameUtil.ApplyFont(icon.Count, globalConfig, config)

    if icon.itemId and (not config or config.showStackCount ~= false) then
        local count = C_Item.GetItemCount(icon.itemId)
        if count and count > 1 then
            setIconCountText(icon, count)
            return
        end
    end

    if icon.spellId and (not config or config.showCharges ~= false) then
        local charges = C_Spell.GetSpellCharges(icon.spellId)
        if charges and charges.maxCharges and charges.maxCharges > 1 and charges.currentCharges ~= nil then
            setIconCountText(icon, charges.currentCharges)
            return
        end
    end

    setIconCountText(icon, nil)
end

--- Caches and returns the cooldown number font from a sibling Blizzard icon.
--- ELI5: copy Blizzard's number style so ECM's extra icons look like they
--- belong in the same row.
local function getSiblingFont(viewer)
    local cached = viewer.__ecmCDFont
    if cached then return cached[1], cached[2], cached[3] end

    for _, child in ipairs({ viewer:GetChildren() }) do
        local cooldown = child.Cooldown
        if cooldown and cooldown.GetRegions then
            local region = cooldown:GetRegions()
            if region and region.IsObjectType and region:IsObjectType("FontString") and region.GetFont then
                local fp, fs, ff = region:GetFont()
                if fp and fs then
                    viewer.__ecmCDFont = { fp, fs, ff }
                    return fp, fs, ff
                end
            end
        end
    end
end

local function getFrameValue(frame, methodName)
    -- Diagnostics should never create a new error while trying to describe the
    -- original problem, so every optional frame read is protected.
    if not frame or type(frame[methodName]) ~= "function" then
        return nil
    end

    local ok, value = pcall(frame[methodName], frame)
    if ok then
        return value
    end

    return nil
end

local function getItemFramesCount(itemFrames)
    -- Count Blizzard's item frame array only when Lua is allowed to read it.
    -- Some protected/tainted tables must not be iterated directly.
    if type(itemFrames) ~= "table" or not canAccessTable(itemFrames) then
        return nil
    end

    local count = 0
    local ok = pcall(function()
        for index in ipairs(itemFrames) do
            count = index
        end
    end)
    return ok and count or nil
end

local function getCombatState()
    -- Combat state is only extra debug context. If the API is unavailable or
    -- errors in tests, leave it blank instead of failing layout.
    if type(InCombatLockdown) ~= "function" then
        return nil
    end

    local ok, inCombat = pcall(InCombatLockdown)
    return ok and inCombat == true or nil
end

local function getViewerDiagnostics(blizzFrame, viewerKey, why, itemFrames)
    -- Build a small snapshot for error logs so bug reports explain what the
    -- Blizzard viewer looked like when ECM could not safely read its children.
    local itemFramesAccessible = nil
    if type(itemFrames) == "table" then
        itemFramesAccessible = canAccessTable(itemFrames)
    end

    return {
        viewerKey = viewerKey,
        blizzardFrameKey = BLIZZ_KEY[viewerKey],
        reason = why,
        viewerExists = blizzFrame ~= nil,
        viewerName = getFrameValue(blizzFrame, "GetName"),
        viewerShown = getFrameValue(blizzFrame, "IsShown"),
        viewerWidth = getFrameValue(blizzFrame, "GetWidth"),
        viewerHeight = getFrameValue(blizzFrame, "GetHeight"),
        viewerAlpha = getFrameValue(blizzFrame, "GetAlpha"),
        viewerNumPoints = getFrameValue(blizzFrame, "GetNumPoints"),
        viewerIconScale = blizzFrame and blizzFrame.iconScale or nil,
        viewerChildXPadding = blizzFrame and blizzFrame.childXPadding or nil,
        viewerHasGetItemFrames = blizzFrame ~= nil and type(blizzFrame.GetItemFrames) == "function",
        itemFramesType = type(itemFrames),
        itemFramesAccessible = itemFramesAccessible,
        itemFramesArrayCount = getItemFramesCount(itemFrames),
        inCombatLockdown = getCombatState(),
    }
end

local function getAccessibleItemFrames(blizzFrame, viewerKey, why)
    -- Blizzard owns the real cooldown viewer children. Read them carefully:
    -- if another addon or secure code makes the list unsafe, log once and keep
    -- the layout conservative instead of breaking the UI.
    local ok, itemFrames = pcall(blizzFrame.GetItemFrames, blizzFrame)
    if not ok then
        local data = getViewerDiagnostics(blizzFrame, viewerKey, why, nil)
        data.error = tostring(itemFrames)
        ns.ErrorLogOnce("ExtraIcons", "GetItemFrames:" .. viewerKey,
            "Unable to read cooldown viewer item frames for " .. viewerKey .. " during "
            .. tostring(why or "unknown") .. ": " .. tostring(itemFrames), data)
        return nil
    end

    if type(itemFrames) ~= "table" then
        return nil
    end

    if not canAccessTable(itemFrames) then
        ns.ErrorLogOnce("ExtraIcons", "InaccessibleItemFrames:" .. viewerKey,
            "Cooldown viewer item frames are inaccessible for " .. viewerKey .. " during "
            .. tostring(why or "unknown"), getViewerDiagnostics(blizzFrame, viewerKey, why, itemFrames))
        return nil
    end

    return itemFrames
end

--------------------------------------------------------------------------------
-- Module methods
--------------------------------------------------------------------------------

function ExtraIcons:CreateFrame()
    -- Create one invisible parent plus one container per Blizzard viewer. The
    -- containers hold visible extra icons; the anchor frames are invisible
    -- measuring sticks for modules that chain after ExtraIcons.
    local parent = CreateFrame("Frame", "ECMExtraIcons", UIParent)
    parent:SetFrameStrata("MEDIUM")
    parent:SetSize(1, 1)

    self._viewers = {}
    for _, v in ipairs(VIEWERS) do
        local container = CreateFrame("Frame", "ECMExtraIcons_" .. v.key, parent)
        container:SetFrameStrata("MEDIUM")
        container:SetSize(1, 1)

        local anchor = CreateFrame("Frame", "ECMExtraIcons_" .. v.key .. "Anchor", parent)
        anchor:SetFrameStrata("MEDIUM")
        anchor:SetSize(1, 1)
        anchor:Hide()

        self._viewers[v.key] = {
            anchorFrame = anchor,
            container = container,
            iconPool = {},
            originalPoint = nil,
            hooked = false,
        }
    end

    return parent
end

function ExtraIcons:ShouldShow()
    -- ExtraIcons only has something useful to do when the base module is
    -- enabled and at least one Blizzard cooldown viewer row is visible.
    if not BarMixin.FrameProto.ShouldShow(self) then return false end
    for _, v in ipairs(VIEWERS) do
        local frame = _G[v.blizzKey]
        if frame and frame:IsShown() then return true end
    end
    return false
end

--- Returns the logical anchor frame used by chained ECM modules so they
--- inherit the combined width of Blizzard icons plus appended extra icons.
--- ELI5: tell the next module to stand after the whole row, including our
--- added icons, not just after Blizzard's original row.
function ExtraIcons:GetMainViewerAnchor()
    local vs = self._viewers and self._viewers.main
    local anchor = vs and vs.anchorFrame
    if anchor and anchor:IsShown() then return anchor end
    return _G[BLIZZ_KEY.main]
end

function ExtraIcons:_updateSingleViewer(viewerConfig, entries, isEditing, sharedOffsetX, moduleConfig, why)
    -- Lay out one row. If there are no extra icons, restore the Blizzard row to
    -- its saved home position. If there are extras, shift Blizzard left and put
    -- the ECM icons immediately to its right so the combined row stays centered.
    local blizzFrame = _G[viewerConfig.blizzKey]
    local vs = self._viewers[viewerConfig.key]
    if not vs then return false end
    local container = vs.container
    sharedOffsetX = sharedOffsetX or 0
    cachePoint(vs, blizzFrame)

    local items = (not blizzFrame or not blizzFrame:IsShown() or isEditing or #entries == 0)
        and {} or resolveEntries(entries, moduleConfig)

    if #items == 0 then
        applyPoint(vs, blizzFrame, sharedOffsetX)
        if isEditing then vs.originalPoint = nil end
        container:Hide()
        if viewerConfig.ownsAnchor then updateMainViewerAnchor(vs, blizzFrame, nil) end
        return false
    end

    for _, icon in ipairs(vs.iconPool) do icon:Hide() end
    for i = #vs.iconPool + 1, #items do
        vs.iconPool[i] = createIcon(container, DEFAULT_SIZE, viewerConfig.borderScale)
    end

    local fontPath, fontSize, fontFlags = getSiblingFont(blizzFrame)
    local globalConfig = self:GetGlobalConfig()
    local iconSize = DEFAULT_SIZE
    local viewerScale = blizzFrame.iconScale or 1.0
    local spacing = blizzFrame.childXPadding or 0
    local lastActive = nil

    local itemFrames = getAccessibleItemFrames(blizzFrame, viewerConfig.key, why)
    if itemFrames then
        local ok, err = pcall(function()
            for _, itemFrame in ipairs(itemFrames) do
                if itemFrame.isActive then
                    -- Match Blizzard's active icon size. Hidden active frames
                    -- still provide size, but they should not be used as the
                    -- right-side anchor because anchoring to hidden frames can
                    -- make extras jump or disappear.
                    iconSize = itemFrame:GetWidth() or iconSize
                    if itemFrame:IsShown() then lastActive = itemFrame end
                end
            end
        end)
        if not ok then
            iconSize = DEFAULT_SIZE
            lastActive = nil
            local data = getViewerDiagnostics(blizzFrame, viewerConfig.key, why, itemFrames)
            data.error = tostring(err)
            ns.ErrorLogOnce("ExtraIcons", "IterateItemFrames:" .. viewerConfig.key,
                "Unable to iterate cooldown viewer item frames for " .. viewerConfig.key .. " during "
                .. tostring(why or "unknown") .. ": " .. tostring(err), data)
        end
    end

    container:SetScale(viewerScale)

    local totalWidth = #items * iconSize + (#items - 1) * spacing
    container:SetSize(totalWidth, iconSize)

    -- Shift the Blizzard viewer left to keep the combined group centred.
    -- The Blizzard frame auto-sizes to its scaled active icons, so its
    -- on-screen centre already coincides with the original anchor; we only
    -- need to absorb the on-screen width of the gap + extra group.
    local extraOnScreen = (spacing + totalWidth) * viewerScale
    applyPoint(vs, blizzFrame, sharedOffsetX - extraOnScreen / 2)

    local xOffset = 0
    for i, data in ipairs(items) do
        local icon = vs.iconPool[i]
        icon:SetSize(iconSize, iconSize)
        icon.Icon:SetSize(iconSize, iconSize)
        icon.Mask:SetSize(iconSize, iconSize)
        icon.Border:SetSize(iconSize * viewerConfig.borderScale[1], iconSize * viewerConfig.borderScale[2])
        icon.slotId = data.slotId
        icon.itemId = data.itemId
        icon.spellId = data.spellId

        icon.Icon:SetTexture(data.texture)
        icon.Icon:SetDesaturated(data.missing == true)
        -- Place each pooled extra icon at its x offset inside the container.
        -- LazySetAnchors skips the work if the icon is already there.
        FrameUtil.LazySetAnchors(icon, { { "LEFT", container, "LEFT", xOffset, 0 } })
        icon:Show()

        updateIconCooldown(icon)
        updateIconCountText(icon, globalConfig, moduleConfig)

        if fontPath and fontSize then
            local region = icon.Cooldown:GetRegions()
            if region and region.IsObjectType and region:IsObjectType("FontString") and region.SetFont then
                region:SetFont(fontPath, fontSize, fontFlags)
            end
        end

        xOffset = xOffset + iconSize + spacing
    end

    -- Attach the container after the last shown Blizzard active icon, or after
    -- the viewer itself if Blizzard has no visible active child to anchor to.
    FrameUtil.LazySetAnchors(container, { { "LEFT", lastActive or blizzFrame, "RIGHT", spacing, 0 } })
    container:Show()

    if viewerConfig.ownsAnchor then updateMainViewerAnchor(vs, blizzFrame, container) end
    return true
end

function ExtraIcons:UpdateLayout(why)
    -- This is the main layout entry point. It resolves configured entries,
    -- updates both viewer rows, keeps shared rows centered, and then refreshes
    -- cooldown/count text for any icons that were placed.
    if not self.InnerFrame or not self._viewers then return false end

    local shouldShow = self:ShouldShow()
    local moduleConfig = self:GetModuleConfig()
    local isEditing = self._isEditModeActive
    if isEditing == nil then
        local mgr = _G.EditModeManagerFrame
        isEditing = mgr and mgr:IsShown() or false
    end

    -- When hidden, leave viewers nil so each call gets empty entries, which
    -- restores Blizzard viewer positions and hides extra-icon containers.
    local viewers = shouldShow and moduleConfig and moduleConfig.viewers
    local offsets = getSharedOffsets(self._viewers, why)
    local anyPlaced = false

    for _, v in ipairs(VIEWERS) do
        local entries = viewers and viewers[v.key] or {}
        if self:_updateSingleViewer(v, entries, isEditing, offsets[v.key], moduleConfig, why) then
            anyPlaced = true
        end
    end

    -- ApplyFramePosition is bypassed because UpdateLayout is overridden, so
    -- manage InnerFrame visibility here.
    if shouldShow then
        if not self.InnerFrame:IsShown() then self.InnerFrame:Show() end
    else
        self.InnerFrame:Hide()
    end

    if anyPlaced then
        ns.Log(self.Name, "UpdateLayout (" .. (why or "") .. ")")
        self:ThrottledRefresh("UpdateLayout")
    end

    return anyPlaced
end

function ExtraIcons:Refresh(why, force)
    -- Refresh is lighter than layout: it keeps existing icons in place and only
    -- updates timers/counts that can change while the row is already visible.
    if not BarMixin.FrameProto.Refresh(self, why, force) then return false end
    if not self._viewers then return false end

    local refreshed = false
    local moduleConfig = self.GetModuleConfig and self:GetModuleConfig() or nil
    local globalConfig = self:GetGlobalConfig()
    for _, vs in pairs(self._viewers) do
        if vs.container and vs.container:IsShown() then
            for _, icon in ipairs(vs.iconPool) do
                if icon:IsShown() and (icon.slotId or icon.itemId or icon.spellId) then
                    updateIconCooldown(icon)
                    updateIconCountText(icon, globalConfig, moduleConfig)
                end
            end
            refreshed = true
        end
    end
    if refreshed then
        ns.Log(self.Name, "Refresh complete (" .. (why or "") .. ")")
    end
    return refreshed
end

--------------------------------------------------------------------------------
-- Events and hooks
--------------------------------------------------------------------------------

function ExtraIcons:OnBagUpdateCooldown()
    -- Bag item cooldowns can change without a full layout change, so only
    -- refresh the visible cooldown swipes.
    self:ThrottledRefresh("OnBagUpdateCooldown")
end

function ExtraIcons:OnBagUpdateDelayed()
    -- Bag contents changed. Re-resolve entries because an item may have been
    -- gained, consumed, or removed.
    ns.Runtime.RequestLayout("ExtraIcons:OnBagUpdateDelayed")
end

function ExtraIcons:OnPlayerEquipmentChanged(slotId)
    -- Only relayout for watched gear slots. This avoids work when unrelated
    -- equipment changes cannot affect any configured extra icon.
    if self._trackedEquipSlots and self._trackedEquipSlots[slotId] then
        ns.Runtime.RequestLayout("ExtraIcons:OnPlayerEquipmentChanged")
    end
end

function ExtraIcons:OnPlayerEnteringWorld()
    -- Instance/PvP state and Blizzard viewer state can change on zone load, so
    -- rebuild the row after entering the world.
    ns.Runtime.RequestLayout("ExtraIcons:OnPlayerEnteringWorld")
end

function ExtraIcons:OnSpellsChanged()
    -- Talents, racials, or spellbook updates can change which spell entries are
    -- known by the character.
    ns.Runtime.RequestLayout("ExtraIcons:OnSpellsChanged")
end

--- Rebuilds the set of equipment slots referenced by current config.
--- ELI5: make a checklist of gear slots that matter, so equipment events can
--- ignore slots the user never configured.
function ExtraIcons:_rebuildTrackedSlots()
    local tracked = {}
    local config = self:GetModuleConfig()
    if config and config.viewers then
        for _, entries in pairs(config.viewers) do
            for _, entry in ipairs(entries) do
                if not entry.disabled then
                    local stack = entry.stackKey and BUILTIN_STACKS[entry.stackKey]
                    local kind = stack and stack.kind or entry.kind
                    local sid = stack and stack.slotId or entry.slotId
                    if kind == "equipSlot" and sid then tracked[sid] = true end
                end
            end
        end
    end
    self._trackedEquipSlots = tracked
end

function ExtraIcons:HookEditMode()
    -- Edit Mode lets Blizzard move its own frames. Hide ECM extras while the
    -- user is editing, then recache positions after Edit Mode closes.
    local mgr = _G.EditModeManagerFrame
    if not mgr or self._editModeHooked then return end
    self._editModeHooked = true
    self._isEditModeActive = mgr:IsShown()

    mgr:HookScript("OnShow", function()
        if not self:IsEnabled() then
            return
        end
        self._isEditModeActive = true
        if self._viewers then
            for _, vs in pairs(self._viewers) do vs.container:Hide() end
        end
        ns.Runtime.RequestLayout("ExtraIcons:EnterEditMode")
    end)

    mgr:HookScript("OnHide", function()
        if not self:IsEnabled() then
            return
        end
        self._isEditModeActive = false
        ns.Runtime.RequestLayout("ExtraIcons:ExitEditMode")
    end)
end

function ExtraIcons:_hookViewer(viewerKey)
    -- Watch Blizzard viewer show/hide/resize events. Whenever Blizzard changes
    -- the base row, ask ECM to rebuild extras around the new row.
    local blizzKey = BLIZZ_KEY[viewerKey]
    local blizzFrame = _G[blizzKey]
    local vs = self._viewers and self._viewers[viewerKey]
    if not blizzFrame or not vs or vs.hooked then return end
    vs.hooked = true

    blizzFrame:HookScript("OnShow", function()
        if not self:IsEnabled() then
            return
        end
        ns.Runtime.RequestLayout("ExtraIcons:OnShow")
    end)
    blizzFrame:HookScript("OnHide", function()
        if not self:IsEnabled() then
            return
        end
        if vs.container then vs.container:Hide() end
        if vs.anchorFrame then vs.anchorFrame:Hide() end
        ns.Runtime.RequestLayout("ExtraIcons:OnHide")
    end)
    blizzFrame:HookScript("OnSizeChanged", function()
        if not self:IsEnabled() then
            return
        end
        ns.Runtime.RequestLayout("ExtraIcons:OnSizeChanged")
    end)

    ns.Log(self.Name, "Hooked " .. blizzKey)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ExtraIcons:OnInitialize()
    -- Attach the shared bar-frame behavior used by ECM modules.
    BarMixin.AddFrameMixin(self, "ExtraIcons")
end

function ExtraIcons:OnEnable()
    -- Start the module: create frames, register with the layout runtime, track
    -- relevant equipment slots, and subscribe to game events that affect icons.
    self:EnsureFrame()
    ns.Runtime.RegisterFrame(self)
    self:_rebuildTrackedSlots()

    self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() self:OnBagUpdateCooldown() end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function() self:OnBagUpdateDelayed() end)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(_, slotId) self:OnPlayerEquipmentChanged(slotId) end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:OnPlayerEnteringWorld() end)
    self:RegisterEvent("SPELLS_CHANGED", function() self:OnSpellsChanged() end)
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
        self:ThrottledRefresh("OnSpellUpdateCooldown")
    end)

    -- Hook viewers after a short delay to ensure Blizzard frames are loaded.
    C_Timer.After(0.1, function()
        if not self:IsEnabled() then
            return
        end

        self:HookEditMode()
        for _, v in ipairs(VIEWERS) do self:_hookViewer(v.key) end
        ns.Runtime.RequestLayout("ExtraIcons:OnEnable")
    end)
end

function ExtraIcons:OnDisable()
    -- Stop the module and clear cached layout state so the next enable starts
    -- from Blizzard's current frame positions.
    self:UnregisterAllEvents()
    self:UpdateLayout("OnDisable")
    ns.Runtime.UnregisterFrame(self)

    if self._viewers then
        for _, vs in pairs(self._viewers) do vs.originalPoint = nil end
    end
    self._isEditModeActive = nil
    self._trackedEquipSlots = nil
end
