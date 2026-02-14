-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
--
-- WoWUnit tests for SpellColors module.
-- Covers: normal operation, instance (secret values), combat lockdown,
--         and post-edit-mode re-style.
--
-- Tests are split into event-driven groups so they run at the moments
-- that matter in production:
--
--   Core          PLAYER_LOGIN            Full API surface.
--   Combat        PLAYER_REGEN_DISABLED   Entering combat + aura updates.
--                 PLAYER_REGEN_ENABLED    Leaving combat.
--                 UNIT_AURA               Spell casts during combat.
--   Zone          ZONE_CHANGED_NEW_AREA   Instance enter/leave.
--                 PLAYER_ENTERING_WORLD   Login, reload, portals.
--   EditMode      PLAYER_LOGIN            Post-edit-mode re-style cycle.
--
-- TAINT NOTE: We must NEVER use WoWUnit.Replace on Blizzard globals
-- (issecretvalue, canaccessvalue, InCombatLockdown, UnitClass, etc.).
-- Writing to _G from addon code permanently taints those globals for the
-- session, breaking secure execution paths in the buff bar system.
--
-- Instance dimension: When aura data is secret inside instances,
-- validateKey() returns nil for both keys.  We exercise this same code
-- path by passing nil keys directly — PriorityKeyMap then receives
-- (nil, nil) and behaves identically to the secret-value case.
--
-- Combat dimension: SpellColors never calls InCombatLockdown; the combat
-- guard lives in BuffBars.style_child_frame.  We verify SpellColors is
-- combat-agnostic by confirming the public API returns correct values
-- regardless of when the tests run.

if not WoWUnit then return end

---------------------------------------------------------------------------
-- WoWUnit aliases
---------------------------------------------------------------------------

local AreEqual = WoWUnit.AreEqual
local IsTrue   = WoWUnit.IsTrue
local IsFalse  = WoWUnit.IsFalse

---------------------------------------------------------------------------
-- Module under test
---------------------------------------------------------------------------

local SC = ECM.SpellColors

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Builds a mock bar frame matching the structure that
--- FrameUtil.GetIconTexture / GetIconTextureFileID expects.
---@param spellName string|nil
---@param textureFileID number|nil
---@param spellID number|nil
---@param cooldownID number|nil
---@return table frame  Mimics ECM_BuffBarMixin
local function makeMockBar(spellName, textureFileID, spellID, cooldownID)
    local mockTexture = {
        IsObjectType = function(_, t) return t == "Texture" end,
        GetTextureFileID = function() return textureFileID end,
    }
    return {
        __ecmHooked = true,
        Name = {
            GetText = function() return spellName end,
        },
        Icon = {
            -- GetRegions returns the texture as the first region (index 1)
            GetRegions = function() return mockTexture end,
        },
        cooldownInfo = spellID and { spellID = spellID } or nil,
        cooldownID = cooldownID,
    }
end

--- Creates a simple color table.
---@param r number
---@param g number
---@param b number
---@return ECM_Color
local function color(r, g, b)
    return { r = r, g = g, b = b, a = 1 }
end

--- Asserts two colors have matching r, g, b fields.
local function assertColorMatch(expected, actual)
    IsTrue(actual)
    AreEqual(expected.r, actual.r)
    AreEqual(expected.g, actual.g)
    AreEqual(expected.b, actual.b)
end

---------------------------------------------------------------------------
--  CORE — PLAYER_LOGIN
--  Full API surface validation.  Runs once at login.
---------------------------------------------------------------------------

local Core = WoWUnit("ECM SpellColors Core")

function Core:GetColor_Unknown_ReturnsNil()
    local result = SC.GetColor("ecm_test_unknown_xyz_987", nil, nil, 99999)
    IsFalse(result)
end

function Core:SetAndGetColor_ByName()
    local name = "ECMTest_Core_ByName"
    local c = color(1, 0, 0)
    SC.SetColor(name, nil, nil, nil, c)

    local got = SC.GetColor(name, nil, nil, nil)
    assertColorMatch(c, got)

    SC.ResetColor(name, nil, nil, nil)
end

function Core:SetAndGetColor_ByTexture()
    local tid = 700001
    local c = color(0, 1, 0)
    SC.SetColor(nil, nil, nil, tid, c)

    local got = SC.GetColor(nil, nil, nil, tid)
    assertColorMatch(c, got)

    SC.ResetColor(nil, nil, nil, tid)
end

function Core:SetAndGetColor_BothKeys()
    local name = "ECMTest_Core_Both"
    local tid = 700004
    local c = color(0, 0, 1)
    SC.SetColor(name, nil, nil, tid, c)

    local byName = SC.GetColor(name, nil, nil, nil)
    assertColorMatch(c, byName)

    local byTex = SC.GetColor(nil, nil, nil, tid)
    assertColorMatch(c, byTex)

    SC.ResetColor(name, nil, nil, tid)
end

function Core:ResetColor_Clears()
    local name = "ECMTest_Core_Reset"
    local tid = 700005
    SC.SetColor(name, nil, nil, tid, color(0.5, 0.5, 0.5))

    SC.ResetColor(name, nil, nil, tid)
    IsFalse(SC.GetColor(name, nil, nil, tid))
end

function Core:ResetColor_Nonexistent_ReturnsFalse()
    local a, b, c, d = SC.ResetColor("ecm_test_never_set_xyz", nil, nil, 888888)
    IsFalse(a)
    IsFalse(d)
end

function Core:GetDefaultColor_MatchesConstant()
    local def = SC.GetDefaultColor()
    assertColorMatch(ECM.Constants.BUFFBARS_DEFAULT_COLOR, def)
end

function Core:SetDefaultColor_Changes()
    local original = SC.GetDefaultColor()
    local newColor = color(1, 0, 0)

    SC.SetDefaultColor(newColor)
    assertColorMatch(newColor, SC.GetDefaultColor())

    SC.SetDefaultColor(original)
end

function Core:GetAllColors_ContainsSetColors()
    local nameA = "ECMTest_Core_AllA"
    local nameB = "ECMTest_Core_AllB"
    local cA = color(0.1, 0.2, 0.3)
    local cB = color(0.4, 0.5, 0.6)

    SC.SetColor(nameA, nil, nil, nil, cA)
    SC.SetColor(nameB, nil, nil, nil, cB)

    local all = SC.GetAllColors()
    IsTrue(all[nameA])
    IsTrue(all[nameB])
    assertColorMatch(cA, all[nameA])
    assertColorMatch(cB, all[nameB])

    SC.ResetColor(nameA, nil, nil, nil)
    SC.ResetColor(nameB, nil, nil, nil)
end

function Core:GetColorForBar_InvalidFrame_ReturnsNil()
    IsFalse(SC.GetColorForBar(nil))
    IsFalse(SC.GetColorForBar({}))
end

function Core:GetColorForBar_ValidMock_ReturnsColor()
    local name = "ECMTest_Core_Bar"
    local tid = 700011
    local c = color(0.8, 0.1, 0.9)
    SC.SetColor(name, nil, nil, tid, c)

    local frame = makeMockBar(name, tid)
    assertColorMatch(c, SC.GetColorForBar(frame))

    SC.ResetColor(name, nil, nil, tid)
end

function Core:ReconcileBar_InvalidFrame_NoError()
    SC.ReconcileBar(nil)
    SC.ReconcileBar({})
    IsTrue(true)
end

function Core:ReconcileAllBars_ReturnsNumber()
    local name = "ECMTest_Core_Rec"
    local tid = 700013
    SC.SetColor(name, nil, nil, tid, color(0.3, 0.3, 0.3))

    local count = SC.ReconcileAllBars({ makeMockBar(name, tid) })
    IsTrue(type(count) == "number")

    SC.ResetColor(name, nil, nil, tid)
end

function Core:NilKeys_GetColor_ReturnsNil()
    SC.SetColor("ECMTest_Core_Nil", nil, nil, 700014, color(0.9, 0.1, 0.1))
    IsFalse(SC.GetColor(nil, nil, nil, nil))
    SC.ResetColor("ECMTest_Core_Nil", nil, nil, 700014)
end

function Core:NilKeys_SetColor_IsNoop()
    local name = "ECMTest_Core_NilSet"
    local tid = 700015
    local original = color(0.2, 0.7, 0.4)
    SC.SetColor(name, nil, nil, tid, original)

    SC.SetColor(nil, nil, nil, nil, color(1, 1, 1))

    assertColorMatch(original, SC.GetColor(name, nil, nil, tid))
    SC.ResetColor(name, nil, nil, tid)
end

function Core:NilKeys_ResetColor_ReturnsFalse()
    local a, b, c, d = SC.ResetColor(nil, nil, nil, nil)
    IsFalse(a)
    IsFalse(d)
end

--- Tests for intermediate key tiers (spellID, cooldownID).
function Core:SetAndGetColor_BySpellID()
    local sid = 800001
    local c = color(0.3, 0.7, 0.1)
    SC.SetColor(nil, sid, nil, nil, c)

    local got = SC.GetColor(nil, sid, nil, nil)
    assertColorMatch(c, got)

    SC.ResetColor(nil, sid, nil, nil)
end

function Core:SetAndGetColor_ByCooldownID()
    local cid = 900001
    local c = color(0.2, 0.4, 0.8)
    SC.SetColor(nil, nil, cid, nil, c)

    local got = SC.GetColor(nil, nil, cid, nil)
    assertColorMatch(c, got)

    SC.ResetColor(nil, nil, cid, nil)
end

function Core:SetByName_GetBySpellID_AfterReconcile()
    local name = "ECMTest_Core_NameToSID"
    local sid = 800002
    local tid = 700016
    local c = color(0.6, 0.1, 0.4)
    SC.SetColor(name, sid, nil, tid, c)

    -- After Set with all keys, spellID tier should have the value.
    local got = SC.GetColor(nil, sid, nil, nil)
    assertColorMatch(c, got)

    SC.ResetColor(name, sid, nil, tid)
end

function Core:SetByTexture_GetByCooldownID_AfterReconcile()
    local cid = 900002
    local tid = 700017
    local c = color(0.9, 0.3, 0.2)
    SC.SetColor(nil, nil, cid, tid, c)

    -- After Set with cooldownID and texture, cooldownID tier should have the value.
    local got = SC.GetColor(nil, nil, cid, nil)
    assertColorMatch(c, got)

    SC.ResetColor(nil, nil, cid, tid)
end

function Core:AllFourKeys_SetAndGet()
    local name = "ECMTest_Core_4Keys"
    local sid = 800003
    local cid = 900003
    local tid = 700018
    local c = color(0.15, 0.85, 0.55)
    SC.SetColor(name, sid, cid, tid, c)

    -- All 4 individual lookups should succeed.
    assertColorMatch(c, SC.GetColor(name, nil, nil, nil))
    assertColorMatch(c, SC.GetColor(nil, sid, nil, nil))
    assertColorMatch(c, SC.GetColor(nil, nil, cid, nil))
    assertColorMatch(c, SC.GetColor(nil, nil, nil, tid))

    SC.ResetColor(name, sid, cid, tid)
end

function Core:GetColorForBar_WithSpellIDAndCooldownID()
    local name = "ECMTest_Core_BarAll"
    local sid = 800004
    local cid = 900004
    local tid = 700019
    local c = color(0.42, 0.58, 0.31)
    SC.SetColor(name, sid, cid, tid, c)

    local frame = makeMockBar(name, tid, sid, cid)
    assertColorMatch(c, SC.GetColorForBar(frame))

    SC.ResetColor(name, sid, cid, tid)
end

function Core:GetColorForBar_OnlySpellID_Fallback()
    -- When spellName and textureFileID are nil (secret), but spellID is available,
    -- the color should still be retrievable.
    local name = "ECMTest_Core_SIDFallback"
    local sid = 800005
    local c = color(0.77, 0.22, 0.55)
    SC.SetColor(name, sid, nil, nil, c)

    -- Simulate a frame where name and texture are secret (nil), only spellID is available.
    local frame = makeMockBar(nil, nil, sid, nil)
    assertColorMatch(c, SC.GetColorForBar(frame))

    SC.ResetColor(name, sid, nil, nil)
end

---------------------------------------------------------------------------
--  COMBAT — PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED, UNIT_AURA
--
--  Runs when entering combat, leaving combat, and on every aura change
--  (the hot path — BuffBars calls GetColorForBar from style_child_frame
--  on UNIT_AURA).  SpellColors is combat-agnostic so all lookups must
--  succeed.  These tests also verify the nil-key (instance) path works
--  correctly even when triggered mid-combat via UNIT_AURA.
---------------------------------------------------------------------------

local Combat = WoWUnit("ECM SpellColors Combat",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "UNIT_AURA"
)

function Combat:GetColor_ReturnsStoredColor()
    local name = "ECMTest_Combat_Get"
    local tid = 700201
    local c = color(0.1, 0.8, 0.3)
    SC.SetColor(name, nil, nil, tid, c)

    assertColorMatch(c, SC.GetColor(name, nil, nil, tid))

    SC.ResetColor(name, nil, nil, tid)
end

function Combat:SetColor_Succeeds()
    local name = "ECMTest_Combat_Set"
    local tid = 700202
    local c = color(0.9, 0.2, 0.5)

    SC.SetColor(name, nil, nil, tid, c)
    assertColorMatch(c, SC.GetColor(name, nil, nil, tid))

    SC.ResetColor(name, nil, nil, tid)
end

function Combat:GetColorForBar_ReturnsStoredColor()
    local name = "ECMTest_Combat_Bar"
    local tid = 700203
    local c = color(0.4, 0.4, 0.8)
    SC.SetColor(name, nil, nil, tid, c)

    assertColorMatch(c, SC.GetColorForBar(makeMockBar(name, tid)))

    SC.ResetColor(name, nil, nil, tid)
end

function Combat:GetDefaultColor_Succeeds()
    local def = SC.GetDefaultColor()
    assertColorMatch(ECM.Constants.BUFFBARS_DEFAULT_COLOR, def)
end

function Combat:GetAllColors_ReturnsTable()
    local name = "ECMTest_Combat_All"
    SC.SetColor(name, nil, nil, nil, color(0.5, 0.5, 0.5))

    local all = SC.GetAllColors()
    IsTrue(type(all) == "table")
    IsTrue(all[name])

    SC.ResetColor(name, nil, nil, nil)
end

function Combat:NilKeys_GetColor_ReturnsNil()
    -- During combat inside an instance, all keys are secret (nil).
    -- Verify the lookup fails gracefully even on UNIT_AURA.
    SC.SetColor("ECMTest_Combat_Nil", nil, nil, 700204, color(0.7, 0.2, 0.1))
    IsFalse(SC.GetColor(nil, nil, nil, nil))
    SC.ResetColor("ECMTest_Combat_Nil", nil, nil, 700204)
end

function Combat:NilKeys_GetColorForBar_ReturnsNil()
    -- Frame returns nil for all keys (instance secret)
    -- during an aura update in combat.
    SC.SetColor("ECMTest_Combat_NilBar", nil, nil, 700205, color(0.3, 0.6, 0.1))
    IsFalse(SC.GetColorForBar(makeMockBar(nil, nil)))
    SC.ResetColor("ECMTest_Combat_NilBar", nil, nil, 700205)
end

function Combat:ReconcileAllBars_Succeeds()
    local name = "ECMTest_Combat_Rec"
    local tid = 700206
    SC.SetColor(name, nil, nil, tid, color(0.2, 0.2, 0.2))

    local count = SC.ReconcileAllBars({ makeMockBar(name, tid) })
    IsTrue(type(count) == "number")

    SC.ResetColor(name, nil, nil, tid)
end

function Combat:LeaveCombat_BothKeysStillSecret()
    -- Edge case observed in production: on PLAYER_REGEN_ENABLED (leaving
    -- combat) the aura frame data has not yet been declassified — both
    -- spellName and textureFileID are still secret values.  validateKey
    -- strips them to nil, making the stored colour unreachable.
    --
    -- We cannot synthesize secret values from addon code, and passing nil
    -- does NOT exercise the same path — style_child_frame's `or "nil"`
    -- fallback turns nil into the literal string "nil", which is not secret.
    --
    -- Instead, scan the real BuffBarCooldownViewer for bars whose values
    -- are actually secret.  When this test fires at PLAYER_REGEN_ENABLED
    -- inside an instance, real bars will have secret data and we exercise
    -- the true code path.  Outside instances the scan finds nothing and
    -- the test verifies the nil-key fallback instead.

    local name = "ECMTest_Combat_LeaveSecret"
    local tid = 700207
    local c = color(0.65, 0.25, 0.85)
    SC.SetColor(name, nil, nil, tid, c)

    -- Try to find a real bar with secret values from the live viewer.
    local viewer = _G["BuffBarCooldownViewer"]
    local foundSecretBar = false
    if viewer then
        local children = { viewer:GetChildren() }
        for _, child in ipairs(children) do
            if child and child.__ecmHooked and child.Bar then
                local sn = child.Bar.Name and child.Bar.Name.GetText
                    and child.Bar.Name:GetText() or nil
                local tf = ECM.FrameUtil.GetIconTextureFileID(child) or nil
                if sn and issecretvalue(sn) and tf and issecretvalue(tf) then
                    -- Real secret bar found — GetColorForBar must return nil
                    -- because validateKey rejects secret keys.
                    IsFalse(SC.GetColorForBar(child))
                    foundSecretBar = true
                    break
                end
            end
        end
    end

    if not foundSecretBar then
        -- Not in an instance or no secret bars — fall back to the nil-key
        -- path which is the closest we can get without real secrets.
        IsFalse(SC.GetColor(nil, nil, nil, nil))
        IsFalse(SC.GetColorForBar(makeMockBar(nil, nil)))
    end

    -- SetColor with nil keys must not overwrite the stored entry.
    SC.SetColor(nil, nil, nil, nil, color(1, 1, 1))

    -- ReconcileBar with nil keys must not throw or corrupt state.
    SC.ReconcileBar(makeMockBar(nil, nil))

    -- Once secrets clear, the original colour is still intact.
    assertColorMatch(c, SC.GetColor(name, nil, nil, tid))

    SC.ResetColor(name, nil, nil, tid)
end

---------------------------------------------------------------------------
--  ZONE — ZONE_CHANGED_NEW_AREA, PLAYER_ENTERING_WORLD
--
--  Runs on zone transitions: entering/leaving instances, portals,
--  login, and /reload.  These are the moments when aura data flips
--  between normal and secret.  Tests verify colors survive zone changes
--  and that the nil-key (instance) path works at the exact events where
--  it matters in production.
---------------------------------------------------------------------------

local Zone = WoWUnit("ECM SpellColors Zone",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD"
)

function Zone:GetColor_ReturnsStoredColor()
    -- Colors set before a zone change must survive the transition.
    local name = "ECMTest_Zone_Get"
    local tid = 700301
    local c = color(0.55, 0.33, 0.77)
    SC.SetColor(name, nil, nil, tid, c)

    assertColorMatch(c, SC.GetColor(name, nil, nil, tid))

    SC.ResetColor(name, nil, nil, tid)
end

function Zone:GetColorForBar_ReturnsStoredColor()
    local name = "ECMTest_Zone_Bar"
    local tid = 700302
    local c = color(0.22, 0.66, 0.44)
    SC.SetColor(name, nil, nil, tid, c)

    assertColorMatch(c, SC.GetColorForBar(makeMockBar(name, tid)))

    SC.ResetColor(name, nil, nil, tid)
end

function Zone:GetDefaultColor_Unchanged()
    assertColorMatch(ECM.Constants.BUFFBARS_DEFAULT_COLOR, SC.GetDefaultColor())
end

function Zone:GetAllColors_ReturnsTable()
    local name = "ECMTest_Zone_All"
    SC.SetColor(name, nil, nil, nil, color(0.6, 0.3, 0.9))

    local all = SC.GetAllColors()
    IsTrue(type(all) == "table")
    IsTrue(all[name])

    SC.ResetColor(name, nil, nil, nil)
end

function Zone:ReconcileAllBars_Succeeds()
    local name = "ECMTest_Zone_Rec"
    local tid = 700303
    SC.SetColor(name, nil, nil, tid, color(0.1, 0.1, 0.1))

    local count = SC.ReconcileAllBars({ makeMockBar(name, tid) })
    IsTrue(type(count) == "number")

    SC.ResetColor(name, nil, nil, tid)
end

function Zone:NilKeys_GetColor_ReturnsNil()
    -- Entering an instance: aura data becomes secret, validateKey strips
    -- keys to nil.  The stored color is unreachable.
    SC.SetColor("ECMTest_Zone_Nil", nil, nil, 700304, color(0.9, 0.1, 0.1))
    IsFalse(SC.GetColor(nil, nil, nil, nil))
    SC.ResetColor("ECMTest_Zone_Nil", nil, nil, 700304)
end

function Zone:NilKeys_GetColorForBar_ReturnsNil()
    SC.SetColor("ECMTest_Zone_NilBar", nil, nil, 700305, color(0.5, 0.5, 0.5))
    IsFalse(SC.GetColorForBar(makeMockBar(nil, nil)))
    SC.ResetColor("ECMTest_Zone_NilBar", nil, nil, 700305)
end

function Zone:NilKeys_ReconcileBar_NoError()
    -- ReconcileBar with a frame returning nil keys (instance) must not throw.
    SC.ReconcileBar(makeMockBar(nil, nil))
    IsTrue(true)
end

function Zone:NilKeys_SetColor_IsNoop()
    local name = "ECMTest_Zone_NilSet"
    local tid = 700306
    local original = color(0.2, 0.7, 0.4)
    SC.SetColor(name, nil, nil, tid, original)

    -- Inside instance, SetColor with nil keys can't overwrite anything.
    SC.SetColor(nil, nil, nil, nil, color(1, 1, 1))
    assertColorMatch(original, SC.GetColor(name, nil, nil, tid))

    SC.ResetColor(name, nil, nil, tid)
end

function Zone:NilKeys_ResetColor_ReturnsFalse()
    local a, b, c, d = SC.ResetColor(nil, nil, nil, nil)
    IsFalse(a)
    IsFalse(d)
end

---------------------------------------------------------------------------
--  EDITMODE — PLAYER_LOGIN
--
--  Edit mode exit triggers ResetStyledMarkers + full re-layout in
--  BuffBars.  SpellColors state lives in SavedVariables, so colors must
--  survive the re-style cycle.  These tests set a colour then perform
--  the same operations BuffBars runs after edit mode (reconcile + bar
--  lookups), including under instance conditions.
---------------------------------------------------------------------------

local EditMode = WoWUnit("ECM SpellColors EditMode")

function EditMode:ColorsPreserved()
    local name = "ECMTest_Edit_Pres"
    local tid = 700401
    local c = color(0.55, 0.33, 0.77)
    SC.SetColor(name, nil, nil, tid, c)

    -- After edit mode, every visible bar is re-styled.  The stored colour
    -- must still be retrievable from the DB.
    assertColorMatch(c, SC.GetColor(name, nil, nil, tid))

    SC.ResetColor(name, nil, nil, tid)
end

function EditMode:ReconcileAllBars_Works()
    local name = "ECMTest_Edit_Rec"
    local tid = 700402
    SC.SetColor(name, nil, nil, tid, color(0.1, 0.1, 0.1))

    -- Edit-mode exit calls ReconcileAllBars on all visible frames.
    local count = SC.ReconcileAllBars({ makeMockBar(name, tid) })
    IsTrue(type(count) == "number")

    SC.ResetColor(name, nil, nil, tid)
end

function EditMode:GetColorForBar_Works()
    local name = "ECMTest_Edit_Bar"
    local tid = 700403
    local c = color(0.22, 0.66, 0.44)
    SC.SetColor(name, nil, nil, tid, c)

    assertColorMatch(c, SC.GetColorForBar(makeMockBar(name, tid)))

    SC.ResetColor(name, nil, nil, tid)
end

function EditMode:NilKeys_GetColor_ReturnsNil()
    -- Edit-mode exit inside an instance — live frame values are secret,
    -- so lookup returns nil even though the colour is in the DB.
    SC.SetColor("ECMTest_Edit_Nil", nil, nil, 700404, color(0.3, 0.3, 0.3))
    IsFalse(SC.GetColor(nil, nil, nil, nil))
    SC.ResetColor("ECMTest_Edit_Nil", nil, nil, 700404)
end
