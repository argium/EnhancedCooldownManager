# Documentation Map

Authoritative source for repo-wide agent rules. Topic-specific docs own their own surface — do not duplicate their content here.

| Doc | Owns |
|---|---|
| [README.md](README.md) | User-facing overview, install, configuration |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Module boundaries, init chain, event flow, public APIs |
| [Libs/LibSettingsBuilder/README.md](Libs/LibSettingsBuilder/README.md) | Settings builder API and schema |
| [Libs/LibConsole/README.md](Libs/LibConsole/README.md) | Slash-command library |
| [Libs/LibEvent/README.md](Libs/LibEvent/README.md) | Embeddable event system |
| [Libs/LibLSMSettingsWidgets/README.md](Libs/LibLSMSettingsWidgets/README.md) | LSM picker templates |

Keep `ARCHITECTURE.md` current for addon-level design changes; each library's README owns its own quick-start, API, and tests.

---

# Validation

```sh
busted Tests                         # addon
busted --run libsettingsbuilder      # per-library suites
busted --run libconsole
busted --run libevent
busted --run liblsmsettingswidgets
luacheck . -q
```

- Changes to `Modules/`, `UI/`, or any root-level `*.lua` must pass `busted Tests` and `luacheck . -q`.
- Changes under `Libs/<Name>/` must additionally pass that library's suite.

---

# Core Rules

All Lua files start with:

```lua
-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
```

## Architecture and Boundaries

- Prefer the simplest production code that satisfies current supported runtime requirements. No fallback paths, compatibility branches, or defensive adapters without a concrete supported environment that needs them.
- Single source of truth for shared state and derived values: derive once, store once, read everywhere.
- Loose coupling via events, hooks, callbacks, or messages.
- No duplicated utilities or trivial passthrough wrappers — extend the canonical owner.
- Don't extract a helper, wrapper, or abstraction unless it has an independently testable contract or 2+ callers.
- No production-only indirection around fixed literals or stable signatures. Pass the value directly.
- Prefer constant lookup tables over pure mapping functions for small fixed domains.
- Remove dead code, stale fields, impossible branches, unused locale strings.
- Clear critical state flags via `pcall` so one error can't wedge later work.

## State and Style

- Mutable state belongs on the owning instance (`self._field`), not file-level locals. Prefix private fields/methods with `_`.
- No forward declarations. Alias shared modules once at file scope.
- Prefer assertions for required parameters over guards and fallbacks.
- Target WoW Lua 5.1 — no `goto`, labels, or `//`.
- No compatibility shims for built-ins WoW already provides. Shims that exist only for `busted` must be documented as such.

## Performance

- Never use `OnUpdate` or frame-rate tickers; use event-driven updates plus a single deferred timer when needed.
- Reuse hot-path tables with `wipe()`. Avoid snapshot-copying callback lists.
- Cancel superseded timers before scheduling new deferred work.
- Periodic setup must stop once all targets are handled.
- Defer once when leaving restricted contexts; don't stack `C_Timer.After(0)` chains.
- Guard hot-path debug logs with `if ECM.IsDebugEnabled() then`.

## Code Density

- Inline single-use locals into their sole call site.
- Generate repeated structural literals from a constructor; extract a thin wrapper for repeated 2–3 call sequences.
- `O(1)` set lookups over linear scans for fixed load-time lists.
- Compact single-line bodies for trivial functions.
- Don't assign fields to `nil` to "clear" them — only assign fields that will be read later.
- Closures differing only in one value should share a parameterised path.

## Tests

- Be skeptical when changing tests to satisfy failures — the failure may be real.
- Test load order mirrors TOC load order. Test files mirror source paths; library tests live under `Libs/<Name>/Tests/`.
- Test production code directly. Don't mirror or reimplement production logic in specs.
- Stub the canonical function, not a wrapper or alias. If a stub diverges from real behavior, fix the stub — don't add fallbacks to live code.
- Reuse `Tests/TestHelpers.lua` before creating new shared helpers.
- `StaticPopup_Show` stubs forward `(name, text1, text2, data)` and call `OnAccept(self, data)`.
- Shared confirm dialogs use `ECM.OptionUtil.MakeConfirmDialog(text)` with `data.onAccept`.

## Libraries and Migrations

- Libraries stay self-contained: no ECM internals; tests and docs live with the library; public API changes are intentional and documented.
- Frame templates must be defined in `.xml`, not via Lua hooks on Blizzard functions like `Settings.CreateElementInitializer`. XML virtual templates with `mixin="GlobalMixinName"` are inherently multi-addon safe via LibStub.
- Migrations in `Migration.lua` are frozen snapshots and must not depend on live production code.
- A single style/metric must have a single owner. If a library renders a widget, the library owns its dimensions, padding, fonts, and colors — callers must not redeclare those values, even via "override" knobs that happen to match the default. If every caller would pass the same value, delete the knob and bake it into the library. Override hooks are only justified when callers genuinely need different values.

---

# Review Heuristics

Optimize for simple, explicit, maintainable code. Watch for unused variables, redundant guards, duplication, tight coupling, needless complexity, missing coverage, and avoidable allocations.

---

# Secret Values

Treat `UnitPowerMax`, `UnitPower`, `UnitPowerPercent`, and `C_UnitAuras.GetUnitAuraBySpellID` as secret values.

- Only nil-check them or pass them to built-ins/APIs that accept secrets.
- No arithmetic, comparisons, boolean tests, length, indexing, assignment, iteration, or use as table keys.
- Storing in locals/upvalues/table values is fine; concatenation and string formatting with string/number secrets is fine.
- Secret tables may yield secret values or be fully inaccessible; `canaccesstable(table)` only reports access, not contents.
- Don't nil-check or wrap built-ins like `issecretvalue`, `issecrettable`, `canaccesstable`.

---

# Deprecated Blizzard APIs (12.0.5)

Do not use the functions, constants, or mixins listed below — they are backward-compat shims and may be removed. Use the modern replacement (typically a `C_*` namespace method or mixin method) shown in Blizzard source: https://github.com/Gethe/wow-ui-source/tree/12.0.5/Interface/AddOns (`Blizzard_Deprecated*` folders).

## Blizzard_Deprecated

`GetBattlefieldScore`, `GetBattlefieldStatData`, `UnitIsSpellTarget`, `C_SpellBook.GetSpellBookItemLossOfControlCooldown`

## Blizzard_DeprecatedChatInfo

Constants: `CHAT_BUTTON_FLASH_TIME`, `CHAT_TELL_ALERT_TIME`, `MAX_COMMUNITY_NAME_LENGTH`, `MAX_COMMUNITY_NAME_LENGTH_NO_CHANNEL`, `MAX_REMEMBERED_TELLS`, `MESSAGE_SCROLLBUTTON_INITIAL_DELAY`, `MESSAGE_SCROLLBUTTON_SCROLL_DELAY`, `MAX_WOW_CHAT_CHANNELS`, `MAX_CHARACTER_NAME_BYTES`, `NUM_CHAT_WINDOWS`, `MAX_COUNTDOWN_SECONDS`

ChatFrameUtil aliases: `Chat_AddSystemMessage`, `Chat_GetChannelColor`, `Chat_GetChannelShortcutName`, `Chat_GetChatCategory`, `Chat_GetChatFrame`, `Chat_GetColoredChatName`, `Chat_GetCommunitiesChannel`, `Chat_GetCommunitiesChannelColor`, `Chat_GetCommunitiesChannelName`, `Chat_ShouldColorChatByClass`, `ChatEdit_ActivateChat`, `ChatEdit_ChooseBoxForSend`, `ChatEdit_DeactivateChat`, `ChatEdit_FocusActiveWindow`, `ChatEdit_GetActiveChatType`, `ChatEdit_GetActiveWindow`, `ChatEdit_GetLastActiveWindow`, `ChatEdit_GetLastTellTarget`, `ChatEdit_GetLastToldTarget`, `ChatEdit_GetNextTellTarget`, `ChatEdit_HasStickyFocus`, `ChatEdit_InsertLink`, `ChatEdit_LinkItem`, `ChatEdit_SetLastActiveWindow`, `ChatEdit_SetLastTellTarget`, `ChatEdit_SetLastToldTarget`, `ChatEdit_TryInsertChatLink`, `ChatEdit_TryInsertQuestLinkForQuestID`, `ChatFrame_AddCommunitiesChannel`, `ChatFrame_AddMessageEventFilter`, `ChatFrame_CanAddChannel`, `ChatFrame_CanChatGroupPerformExpressionExpansion`, `ChatFrame_ChatPageDown`, `ChatFrame_ChatPageUp`, `ChatFrame_ClearChatFocusOverride`, `ChatFrame_DisplayChatHelp`, `ChatFrame_DisplayGameTime`, `ChatFrame_DisplayGMOTD`, `ChatFrame_DisplayHelpText`, `ChatFrame_DisplayHelpTextSimple`, `ChatFrame_DisplayMacroHelpText`, `ChatFrame_DisplaySystemMessage`, `ChatFrame_DisplaySystemMessageInCurrent`, `ChatFrame_DisplaySystemMessageInPrimary`, `ChatFrame_DisplayTimePlayed`, `ChatFrame_DisplayUsageError`, `ChatFrame_GetChatFocusOverride`, `ChatFrame_GetCommunitiesChannelLocalID`, `ChatFrame_GetCommunityAndStreamFromChannel`, `ChatFrame_GetCommunityAndStreamName`, `ChatFrame_GetFullChannelInfo`, `ChatFrame_GetMobileEmbeddedTexture`, `ChatFrame_OpenChat`, `ChatFrame_RemoveCommunitiesChannel`, `ChatFrame_RemoveMessageEventFilter`, `ChatFrame_ReplyTell`, `ChatFrame_ReplyTell2`, `ChatFrame_ResolveChannelName`, `ChatFrame_ResolvePrefixedChannelName`, `ChatFrame_ScrollDown`, `ChatFrame_ScrollToBottom`, `ChatFrame_ScrollUp`, `ChatFrame_SendTell`, `ChatFrame_SendTellWithMessage`, `ChatFrame_SetChatFocusOverride`, `ChatFrame_TimeBreakDown`, `ChatFrame_TruncateToMaxLength`, `ChatFrame_UpdateChatFrames`, `GetChatTimestampFormat`, `SubstituteChatMessageBeforeSend`

ChatFrameMixin aliases: `ChatFrame_AddMessage`, `ChatFrame_AddMessageGroup`, `ChatFrame_AddPrivateMessageTarget`, `ChatFrame_AddSingleMessageType`, `ChatFrame_ContainsChannel`, `ChatFrame_ContainsMessageGroup`, `ChatFrame_ExcludePrivateMessageTarget`, `ChatFrame_GetDefaultChatTarget`, `ChatFrame_ReceiveAllPrivateMessages`, `ChatFrame_RegisterForChannels`, `ChatFrame_RegisterForMessages`, `ChatFrame_RemoveAllChannels`, `ChatFrame_RemoveAllMessageGroups`, `ChatFrame_RemoveChannel`, `ChatFrame_RemoveExcludePrivateMessageTarget`, `ChatFrame_RemoveMessageGroup`, `ChatFrame_RemovePrivateMessageTarget`, `ChatFrame_UnregisterAllMessageGroups`, `ChatFrame_UpdateColorByID`, `ChatFrame_UpdateDefaultChatTarget`

ChatFrameEditBoxMixin aliases: `ChatEdit_AddHistory`, `ChatEdit_ClearChat`, `ChatEdit_DoesCurrentChannelTargetMatch`, `ChatEdit_ExtractChannel`, `ChatEdit_ExtractTellTarget`, `ChatEdit_GetChannelTarget`, `ChatEdit_HandleChatType`, `ChatEdit_ParseText`, `ChatEdit_ResetChatType`, `ChatEdit_ResetChatTypeToSticky`, `ChatEdit_SendText`, `ChatEdit_SetDeactivated`, `ChatEdit_UpdateHeader`

API: `SendChatMessage`, `DoEmote`, `CancelEmote`

## Blizzard_DeprecatedInstanceEncounter

`IsEncounterInProgress`, `IsEncounterSuppressingRelease`, `IsEncounterLimitingResurrections`

## Blizzard_DeprecatedItemScript

`GetItemQualityColor`, `GetItemInfoInstant`, `GetItemSetInfo`, `GetItemChildInfo`, `DoesItemContainSpec`, `GetItemGem`, `GetItemCreationContext`, `GetItemIcon`, `GetItemFamily`, `GetItemSpell`, `IsArtifactPowerItem`, `IsCurrentItem`, `IsUsableItem`, `IsHelpfulItem`, `IsHarmfulItem`, `IsConsumableItem`, `IsEquippableItem`, `IsEquippedItem`, `IsEquippedItemType`, `ItemHasRange`, `IsItemInRange`, `GetItemClassInfo`, `GetItemInventorySlotInfo`, `BindEnchant`, `ActionBindsItem`, `ReplaceEnchant`, `ReplaceTradeEnchant`, `ConfirmBindOnUse`, `ConfirmOnUse`, `ConfirmNoRefundOnUse`, `DropItemOnUnit`, `EndBoundTradeable`, `EndRefund`, `GetItemInfo`, `GetDetailedItemLevelInfo`, `GetItemSpecInfo`, `GetItemUniqueness`, `GetItemCount`, `PickupItem`, `GetItemSubClassInfo`, `UseItemByName`, `EquipItemByName`, `ReplaceTradeskillEnchant`, `GetItemCooldown`, `IsCorruptedItem`, `IsCosmeticItem`, `IsDressableItem`

## Blizzard_DeprecatedPvpScript

`IsSubZonePVPPOI`, `GetZonePVPInfo`, `TogglePVP`, `SetPVP`

## Blizzard_DeprecatedSpecialization

Standard: `GetNumSpecializationsForClassID`, `GetSpecializationInfo`, `GetSpecialization`, `GetActiveSpecGroup`, `GetSpecializationMasterySpells`, `GetTalentInfo`

Classic: `SetActiveTalentGroup`, `GetTalentTabInfo`, `GetPrimaryTalentTree`, `GetActiveTalentGroup`, `GetTalentTreeMasterySpells`

Constants: `MAX_TALENT_TIERS`, `NUM_TALENT_COLUMNS`

## Blizzard_DeprecatedSpellBook

`HUNTER_DISMISS_PET`, `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `FindFlyoutSlotBySpellID`, `FindSpellOverrideByID`, `FindBaseSpellByID`

## Blizzard_DeprecatedSpellScript

`TargetSpellReplacesBonusTree`, `GetMaxSpellStartRecoveryOffset`, `GetSpellQueueWindow`, `GetSchoolString`, `SpellIsPriorityAura`, `SpellIsSelfBuff`, `SpellGetVisibilityInfo`, `C_Spell.GetSpellLossOfControlCooldown`
