# Validation

```sh
# Addon tests
busted Tests

# Library tests
busted --run libsettingsbuilder
busted --run libconsole
busted --run libevent
busted --run liblsmsettingswidgets

# Lint
luacheck . -q
```

- Changes to `Modules/`, `Helpers/`, `UI/`, and `ECM*.lua` must pass `busted Tests` and `luacheck . -q`.
- Library changes must also pass that library's dedicated test suite.

---

# Core Rules

<CopyrightHeader>
-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
</CopyrightHeader>

- All Lua files must include the standard copyright header.
- Keep [ARCHITECTURE.md](ARCHITECTURE.md) up to date.


## Lua / WoW Runtime

- Target WoW Lua 5.1; do not use post-5.1 features such as `goto`, labels, or `//`.
- Do not add compatibility shims for built-ins already present in WoW. If a shim exists only for `busted`, document that.
- Do not nil-check or wrap built-ins such as `issecretvalue`, `issecrettable`, or `canaccesstable`.

## Config, Events, and State

- Mutable state belongs on the owning instance (`self._field`), not file-level locals. Prefix private fields and methods with `_`.
- Do not use forward declarations. Alias shared modules once at file scope when reused.

## Performance

- Never use `OnUpdate` or frame-rate tickers; prefer event-driven updates plus a single deferred timer when needed.
- Reuse tables on hot paths with `wipe()`.
- Cancel superseded timers before scheduling new deferred work.
- Guard hot-path debug logging with `if ECM.IsDebugEnabled() then`.
- Avoid snapshot-copying callback lists; use zero-allocation iteration that tolerates removal.
- Periodic setup work must stop doing setup once all targets are handled.
- Defer once out of restricted contexts; avoid stacked `C_Timer.After(0)` chains.

## Architecture and Boundaries

- Prefer loose coupling via events, hooks, callbacks, or messages.
- Prefer the simplest production code that satisfies current supported runtime requirements. Do not add fallback paths, compatibility branches, or defensive adapters unless a concrete supported environment requires them.
- Maintain a single source of truth for shared state and derived values: derive once, store once, read everywhere.
- Do not duplicate utilities or add trivial passthrough wrappers; extend the canonical owner instead.
- Before introducing a helper, wrapper, or abstraction, prove that it reduces real complexity for multiple callers or captures a distinct behavior that needs to be tested independently.
- Do not extract single-use helpers unless they have a clear independently testable contract or 2+ callers.
- Do not add production-only indirection around fixed literal values or stable API signatures. If a call always uses the same simple value, pass it directly unless a shared abstraction has a real runtime need.
- Prefer constant lookup tables over pure mapping functions for small fixed domains.
- Remove dead code, stale fields, impossible branches, and unused locale strings.
- Clear critical state flags with `pcall` or equivalent so one error cannot wedge later work.

## Code Density

- Inline single-use local functions into their sole call site. Do not extract a helper just to give a three-line block a name.
- When multiple table literals share identical structure (e.g. `{ normal = base .. X .. "_normal", pushed = base .. X .. "_down" }`), generate them with a constructor instead of writing each one out.
- When the same two- or three-call sequence repeats across many callbacks (e.g. `scheduleUpdate(); refreshPage()`), extract one thin wrapper and call it everywhere.
- Use `O(1)` set lookups (`SET[key]`) instead of linear scans (`for i, v in ipairs(list)`) when the list is fixed at load time.
- Prefer compact single-line bodies for trivial functions: `local function f() return x end`.
- When building repetitive declarative structures (action buttons, menu items), extract a factory that takes only the varying parts and returns the full structure.
- Do not assign fields to `nil` just to "clear" them. Only assign fields that will be read later.
- Closures that differ only in one value (e.g. direction = -1 vs +1) should call through a shared parameterised path, not duplicate the surrounding code.

## Tests, Libraries, and Migrations

- Be skeptical about changing tests to satisfy failures; the failure may be real.
- If tests diverge from WoW or library runtime behavior, fix the stub or fixture to match production instead of adding fallback paths or compatibility helpers to live code.
- Test load order must mirror TOC load order.
- Stub the canonical function, not a wrapper or alias.
- Test production code directly. Do not mirror, duplicate, or reimplement production logic in specs.
- Reuse `Tests/TestHelpers.lua` before creating new shared test helpers.
- Test files mirror source paths; library tests stay under `Libs/<Name>/Tests/`.
- `StaticPopup_Show` stubs must forward `(name, text1, text2, data)` and call `OnAccept(self, data)`.
- Libraries must stay self-contained: no ECM internals; tests and docs live with the library; public API changes should be intentional and documented.
- Do not use global hooks on Blizzard UI functions (like `Settings.CreateElementInitializer`) to simulate XML templates in pure Lua. Library frame templates must use `.xml` files to prevent widespread execution taint.
- XML-defined virtual frame templates with `mixin="GlobalMixinName"` are inherently multi-addon safe via LibStub: the Lua runs once (defining the global mixin tables), and WoW resolves mixin names lazily at `CreateFrame` time. Do not replace XML templates with Lua-based mixin injection to "support multiple addons" — it breaks the initialization pipeline and causes taint.
- Shared confirm dialogs use `ECM.OptionUtil.MakeConfirmDialog(text)` with `data.onAccept`.
- Migrations in `Helpers/Migration.lua` are frozen snapshots and must not depend on live production code.

---

# Review Heuristics

- Optimize for simple, explicit, maintainable code.
- Watch for unused variables, redundant guards or assignments, duplication, tight coupling, needless complexity, missing coverage, and avoidable allocations.

---

# Secret Values

- Treat `UnitPowerMax`, `UnitPower`, `UnitPowerPercent`, and `C_UnitAuras.GetUnitAuraBySpellID` as secret values.
- Only nil-check them or pass them to built-ins or APIs that accept secrets.
- Do not do arithmetic, comparisons, boolean tests, length, indexing, assignment, iteration, or use them as table keys.
- Storing secret values in locals, upvalues, or table values is allowed; concatenation and string formatting with string or number secrets is allowed.
- Secret tables may always yield secret values or be fully inaccessible; `canaccesstable(table)` only tells you whether access would be allowed.

---

# Deprecated Blizzard APIs (12.0.5)

Do not use any of the functions, constants, or mixins listed below. They are deprecated shims provided by Blizzard for backward compatibility and may be removed in a future patch. Use the modern replacement shown in the Blizzard source (typically a `C_*` namespace method or mixin method) instead.

Source: `Blizzard_Deprecated*` folders in https://github.com/Gethe/wow-ui-source/tree/12.0.5/Interface/AddOns

## Blizzard_Deprecated

- `GetBattlefieldScore`
- `GetBattlefieldStatData`
- `UnitIsSpellTarget`
- `C_SpellBook.GetSpellBookItemLossOfControlCooldown`

## Blizzard_DeprecatedChatInfo

Constants: `CHAT_BUTTON_FLASH_TIME`, `CHAT_TELL_ALERT_TIME`, `MAX_COMMUNITY_NAME_LENGTH`, `MAX_COMMUNITY_NAME_LENGTH_NO_CHANNEL`, `MAX_REMEMBERED_TELLS`, `MESSAGE_SCROLLBUTTON_INITIAL_DELAY`, `MESSAGE_SCROLLBUTTON_SCROLL_DELAY`, `MAX_WOW_CHAT_CHANNELS`, `MAX_CHARACTER_NAME_BYTES`, `NUM_CHAT_WINDOWS`, `MAX_COUNTDOWN_SECONDS`

ChatFrameUtil aliases: `Chat_AddSystemMessage`, `Chat_GetChannelColor`, `Chat_GetChannelShortcutName`, `Chat_GetChatCategory`, `Chat_GetChatFrame`, `Chat_GetColoredChatName`, `Chat_GetCommunitiesChannel`, `Chat_GetCommunitiesChannelColor`, `Chat_GetCommunitiesChannelName`, `Chat_ShouldColorChatByClass`, `ChatEdit_ActivateChat`, `ChatEdit_ChooseBoxForSend`, `ChatEdit_DeactivateChat`, `ChatEdit_FocusActiveWindow`, `ChatEdit_GetActiveChatType`, `ChatEdit_GetActiveWindow`, `ChatEdit_GetLastActiveWindow`, `ChatEdit_GetLastTellTarget`, `ChatEdit_GetLastToldTarget`, `ChatEdit_GetNextTellTarget`, `ChatEdit_HasStickyFocus`, `ChatEdit_InsertLink`, `ChatEdit_LinkItem`, `ChatEdit_SetLastActiveWindow`, `ChatEdit_SetLastTellTarget`, `ChatEdit_SetLastToldTarget`, `ChatEdit_TryInsertChatLink`, `ChatEdit_TryInsertQuestLinkForQuestID`, `ChatFrame_AddCommunitiesChannel`, `ChatFrame_AddMessageEventFilter`, `ChatFrame_CanAddChannel`, `ChatFrame_CanChatGroupPerformExpressionExpansion`, `ChatFrame_ChatPageDown`, `ChatFrame_ChatPageUp`, `ChatFrame_ClearChatFocusOverride`, `ChatFrame_DisplayChatHelp`, `ChatFrame_DisplayGameTime`, `ChatFrame_DisplayGMOTD`, `ChatFrame_DisplayHelpText`, `ChatFrame_DisplayHelpTextSimple`, `ChatFrame_DisplayMacroHelpText`, `ChatFrame_DisplaySystemMessage`, `ChatFrame_DisplaySystemMessageInCurrent`, `ChatFrame_DisplaySystemMessageInPrimary`, `ChatFrame_DisplayTimePlayed`, `ChatFrame_DisplayUsageError`, `ChatFrame_GetChatFocusOverride`, `ChatFrame_GetCommunitiesChannelLocalID`, `ChatFrame_GetCommunityAndStreamFromChannel`, `ChatFrame_GetCommunityAndStreamName`, `ChatFrame_GetFullChannelInfo`, `ChatFrame_GetMobileEmbeddedTexture`, `ChatFrame_OpenChat`, `ChatFrame_RemoveCommunitiesChannel`, `ChatFrame_RemoveMessageEventFilter`, `ChatFrame_ReplyTell`, `ChatFrame_ReplyTell2`, `ChatFrame_ResolveChannelName`, `ChatFrame_ResolvePrefixedChannelName`, `ChatFrame_ScrollDown`, `ChatFrame_ScrollToBottom`, `ChatFrame_ScrollUp`, `ChatFrame_SendTell`, `ChatFrame_SendTellWithMessage`, `ChatFrame_SetChatFocusOverride`, `ChatFrame_TimeBreakDown`, `ChatFrame_TruncateToMaxLength`, `ChatFrame_UpdateChatFrames`, `GetChatTimestampFormat`, `SubstituteChatMessageBeforeSend`

ChatFrameMixin aliases: `ChatFrame_AddMessage`, `ChatFrame_AddMessageGroup`, `ChatFrame_AddPrivateMessageTarget`, `ChatFrame_AddSingleMessageType`, `ChatFrame_ContainsChannel`, `ChatFrame_ContainsMessageGroup`, `ChatFrame_ExcludePrivateMessageTarget`, `ChatFrame_GetDefaultChatTarget`, `ChatFrame_ReceiveAllPrivateMessages`, `ChatFrame_RegisterForChannels`, `ChatFrame_RegisterForMessages`, `ChatFrame_RemoveAllChannels`, `ChatFrame_RemoveAllMessageGroups`, `ChatFrame_RemoveChannel`, `ChatFrame_RemoveExcludePrivateMessageTarget`, `ChatFrame_RemoveMessageGroup`, `ChatFrame_RemovePrivateMessageTarget`, `ChatFrame_UnregisterAllMessageGroups`, `ChatFrame_UpdateColorByID`, `ChatFrame_UpdateDefaultChatTarget`

ChatFrameEditBoxMixin aliases: `ChatEdit_AddHistory`, `ChatEdit_ClearChat`, `ChatEdit_DoesCurrentChannelTargetMatch`, `ChatEdit_ExtractChannel`, `ChatEdit_ExtractTellTarget`, `ChatEdit_GetChannelTarget`, `ChatEdit_HandleChatType`, `ChatEdit_ParseText`, `ChatEdit_ResetChatType`, `ChatEdit_ResetChatTypeToSticky`, `ChatEdit_SendText`, `ChatEdit_SetDeactivated`, `ChatEdit_UpdateHeader`

API functions: `SendChatMessage`, `DoEmote`, `CancelEmote`

## Blizzard_DeprecatedInstanceEncounter

- `IsEncounterInProgress`, `IsEncounterSuppressingRelease`, `IsEncounterLimitingResurrections`

## Blizzard_DeprecatedItemScript

- `GetItemQualityColor`, `GetItemInfoInstant`, `GetItemSetInfo`, `GetItemChildInfo`, `DoesItemContainSpec`, `GetItemGem`, `GetItemCreationContext`, `GetItemIcon`, `GetItemFamily`, `GetItemSpell`
- `IsArtifactPowerItem`, `IsCurrentItem`, `IsUsableItem`, `IsHelpfulItem`, `IsHarmfulItem`, `IsConsumableItem`, `IsEquippableItem`, `IsEquippedItem`, `IsEquippedItemType`
- `ItemHasRange`, `IsItemInRange`, `GetItemClassInfo`, `GetItemInventorySlotInfo`
- `BindEnchant`, `ActionBindsItem`, `ReplaceEnchant`, `ReplaceTradeEnchant`, `ConfirmBindOnUse`, `ConfirmOnUse`, `ConfirmNoRefundOnUse`
- `DropItemOnUnit`, `EndBoundTradeable`, `EndRefund`
- `GetItemInfo`, `GetDetailedItemLevelInfo`, `GetItemSpecInfo`, `GetItemUniqueness`, `GetItemCount`, `PickupItem`, `GetItemSubClassInfo`
- `UseItemByName`, `EquipItemByName`, `ReplaceTradeskillEnchant`, `GetItemCooldown`
- `IsCorruptedItem`, `IsCosmeticItem`, `IsDressableItem`

## Blizzard_DeprecatedPvpScript

- `IsSubZonePVPPOI`, `GetZonePVPInfo`, `TogglePVP`, `SetPVP`

## Blizzard_DeprecatedSpecialization

Standard: `GetNumSpecializationsForClassID`, `GetSpecializationInfo`, `GetSpecialization`, `GetActiveSpecGroup`, `GetSpecializationMasterySpells`, `GetTalentInfo`

Classic variants: `SetActiveTalentGroup`, `GetTalentTabInfo`, `GetPrimaryTalentTree`, `GetActiveTalentGroup`, `GetTalentTreeMasterySpells`

Constants: `MAX_TALENT_TIERS`, `NUM_TALENT_COLUMNS`

## Blizzard_DeprecatedSpellBook

Constant: `HUNTER_DISMISS_PET`

Functions: `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `FindFlyoutSlotBySpellID`, `FindSpellOverrideByID`, `FindBaseSpellByID`

## Blizzard_DeprecatedSpellScript

- `TargetSpellReplacesBonusTree`, `GetMaxSpellStartRecoveryOffset`, `GetSpellQueueWindow`, `GetSchoolString`
- `SpellIsPriorityAura`, `SpellIsSelfBuff`, `SpellGetVisibilityInfo`
- `C_Spell.GetSpellLossOfControlCooldown`
