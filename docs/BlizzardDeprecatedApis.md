# Deprecated Blizzard APIs (12.0.7)

Do not use the functions, constants, aliases, or mixins listed below. They are backward-compatibility shims and may be removed. Use the modern replacement shown in Blizzard source, typically a `C_*` namespace method or mixin method:

https://github.com/Gethe/wow-ui-source/tree/12.0.7/Interface/AddOns

Check the `Blizzard_Deprecated*` folders when choosing the replacement.

## Blizzard_Deprecated

- `GetBattlefieldScore`, `GetBattlefieldStatData`, `UnitIsSpellTarget`, `C_SpellBook.GetSpellBookItemLossOfControlCooldown`, `MenuUtil.ShowTooltip`, `MenuUtil.HideTooltip`, `C_ClickBindings.MakeModifiers`, `C_ClickBindings.GetStringFromModifiers`, `C_Spell.GetMawPowerBorderAtlasBySpellID`, `GetMerchantCurrencies`

## Blizzard_Deprecated_ArenaUI

- Constants: `MAX_ARENA_ENEMIES`
- Mixins: `ArenaEnemyFramesContainerMixin`, `ArenaEnemyMatchFramesContainerMixin`, `ArenaEnemyMatchFrameMixin`, `ArenaEnemyPrepFrameMixin`, `ArenaEnemyPetFrameMixin`, `ArenaEnemyPrepFramesContainerMixin`

## Blizzard_DeprecatedActionBar

- `GetActionAutocast`, `GetActionText`, `GetActionTexture`, `GetActionCount`, `GetActionCooldown`, `GetActionCharges`, `GetActionLossOfControlCooldown`, `HasAction`, `IsAttackAction`, `IsCurrentAction`, `IsAutoRepeatAction`, `IsUsableAction`, `IsConsumableAction`, `IsStackableAction`, `IsItemAction`, `IsEquippedAction`, `ActionHasRange`, `IsActionInRange`, `SetActionUIButton`, `GetBonusBarIndex`, `GetBonusBarOffset`, `GetExtraBarIndex`, `GetMultiCastBarIndex`, `GetOverrideBarIndex`, `GetOverrideBarSkin`, `GetTempShapeshiftBarIndex`, `GetVehicleBarIndex`, `HasBonusActionBar`, `HasExtraActionBar`, `HasOverrideActionBar`, `HasTempShapeshiftActionBar`, `HasVehicleActionBar`, `IsPossessBarVisible`, `ChangeActionBarPage`, `GetActionBarPage`, `C_ActionBar.GetActionLossOfControlCooldown`

## Blizzard_DeprecatedAutoComplete

- Functions: `GetAutoCompletePresenceID`, `GetAutoCompleteResults`, `GetAutoCompleteRealms`, `IsRecognizedName`
- Constants: `AUTOCOMPLETE_FLAG_IN_GROUP`, `AUTOCOMPLETE_FLAG_IN_GUILD`, `AUTOCOMPLETE_FLAG_FRIEND`, `AUTOCOMPLETE_FLAG_BNET`, `AUTOCOMPLETE_FLAG_INTERACTED_WITH`, `AUTOCOMPLETE_FLAG_ONLINE`, `AUTO_COMPLETE_IN_AOI`, `AUTO_COMPLETE_ACCOUNT_CHARACTER`, `AUTO_COMPLETE_RECENT_PLAYER`, `LE_AUTOCOMPLETE_PRIORITY_OTHER`, `LE_AUTOCOMPLETE_PRIORITY_INTERACTED`, `LE_AUTOCOMPLETE_PRIORITY_IN_GROUP`, `LE_AUTOCOMPLETE_PRIORITY_GUILD`, `LE_AUTOCOMPLETE_PRIORITY_FRIEND`, `LE_AUTOCOMPLETE_PRIORITY_ACCOUNT_CHARACTER`, `LE_AUTOCOMPLETE_PRIORITY_ACCOUNT_CHARACTER_SAME_REALM`

## Blizzard_DeprecatedBattleNet

- `BNSendGameData`, `BNSendWhisper`, `BNSetCustomMessage`, `BNInviteFriend`

## Blizzard_DeprecatedChatInfo

- Functions: `Chat_AddSystemMessage`, `Chat_GetChannelColor`, `Chat_GetChannelShortcutName`, `Chat_GetChatCategory`, `Chat_GetChatFrame`, `Chat_GetColoredChatName`, `Chat_GetCommunitiesChannel`, `Chat_GetCommunitiesChannelColor`, `Chat_GetCommunitiesChannelName`, `Chat_ShouldColorChatByClass`, `ChatEdit_ActivateChat`, `ChatEdit_ChooseBoxForSend`, `ChatEdit_DeactivateChat`, `ChatEdit_FocusActiveWindow`, `ChatEdit_GetActiveChatType`, `ChatEdit_GetActiveWindow`, `ChatEdit_GetLastActiveWindow`, `ChatEdit_GetLastTellTarget`, `ChatEdit_GetLastToldTarget`, `ChatEdit_GetNextTellTarget`, `ChatEdit_HasStickyFocus`, `ChatEdit_InsertLink`, `ChatEdit_LinkItem`, `ChatEdit_SetLastActiveWindow`, `ChatEdit_SetLastTellTarget`, `ChatEdit_SetLastToldTarget`, `ChatEdit_TryInsertChatLink`, `ChatEdit_TryInsertQuestLinkForQuestID`, `ChatFrame_AddCommunitiesChannel`, `ChatFrame_AddMessageEventFilter`, `ChatFrame_CanAddChannel`, `ChatFrame_CanChatGroupPerformExpressionExpansion`, `ChatFrame_ChatPageDown`, `ChatFrame_ChatPageUp`, `ChatFrame_ClearChatFocusOverride`, `ChatFrame_DisplayChatHelp`, `ChatFrame_DisplayGameTime`, `ChatFrame_DisplayGMOTD`, `ChatFrame_DisplayHelpText`, `ChatFrame_DisplayHelpTextSimple`, `ChatFrame_DisplayMacroHelpText`, `ChatFrame_DisplaySystemMessage`, `ChatFrame_DisplaySystemMessageInCurrent`, `ChatFrame_DisplaySystemMessageInPrimary`, `ChatFrame_DisplayTimePlayed`, `ChatFrame_DisplayUsageError`, `ChatFrame_GetChatFocusOverride`, `ChatFrame_GetCommunitiesChannelLocalID`, `ChatFrame_GetCommunityAndStreamFromChannel`, `ChatFrame_GetCommunityAndStreamName`, `ChatFrame_GetFullChannelInfo`, `ChatFrame_GetMobileEmbeddedTexture`, `ChatFrame_OpenChat`, `ChatFrame_RemoveCommunitiesChannel`, `ChatFrame_RemoveMessageEventFilter`, `ChatFrame_ReplyTell`, `ChatFrame_ReplyTell2`, `ChatFrame_ResolveChannelName`, `ChatFrame_ResolvePrefixedChannelName`, `ChatFrame_ScrollDown`, `ChatFrame_ScrollToBottom`, `ChatFrame_ScrollUp`, `ChatFrame_SendTell`, `ChatFrame_SendTellWithMessage`, `ChatFrame_SetChatFocusOverride`, `ChatFrame_TimeBreakDown`, `ChatFrame_TruncateToMaxLength`, `ChatFrame_UpdateChatFrames`, `GetChatTimestampFormat`, `SubstituteChatMessageBeforeSend`, `ChatFrame_AddMessage`, `ChatFrame_AddMessageGroup`, `ChatFrame_AddPrivateMessageTarget`, `ChatFrame_AddSingleMessageType`, `ChatFrame_ContainsChannel`, `ChatFrame_ContainsMessageGroup`, `ChatFrame_ExcludePrivateMessageTarget`, `ChatFrame_GetDefaultChatTarget`, `ChatFrame_ReceiveAllPrivateMessages`, `ChatFrame_RegisterForChannels`, `ChatFrame_RegisterForMessages`, `ChatFrame_RemoveAllChannels`, `ChatFrame_RemoveAllMessageGroups`, `ChatFrame_RemoveChannel`, `ChatFrame_RemoveExcludePrivateMessageTarget`, `ChatFrame_RemoveMessageGroup`, `ChatFrame_RemovePrivateMessageTarget`, `ChatFrame_UnregisterAllMessageGroups`, `ChatFrame_UpdateColorByID`, `ChatFrame_UpdateDefaultChatTarget`, `ChatEdit_AddHistory`, `ChatEdit_ClearChat`, `ChatEdit_DoesCurrentChannelTargetMatch`, `ChatEdit_ExtractChannel`, `ChatEdit_ExtractTellTarget`, `ChatEdit_GetChannelTarget`, `ChatEdit_HandleChatType`, `ChatEdit_ParseText`, `ChatEdit_ResetChatType`, `ChatEdit_ResetChatTypeToSticky`, `ChatEdit_SendText`, `ChatEdit_SetDeactivated`, `ChatEdit_UpdateHeader`, `SendChatMessage`, `DoEmote`, `CancelEmote`
- Constants: `CHAT_BUTTON_FLASH_TIME`, `CHAT_TELL_ALERT_TIME`, `MAX_COMMUNITY_NAME_LENGTH`, `MAX_COMMUNITY_NAME_LENGTH_NO_CHANNEL`, `MAX_REMEMBERED_TELLS`, `MESSAGE_SCROLLBUTTON_INITIAL_DELAY`, `MESSAGE_SCROLLBUTTON_SCROLL_DELAY`, `MAX_WOW_CHAT_CHANNELS`, `MAX_CHARACTER_NAME_BYTES`, `NUM_CHAT_WINDOWS`, `MAX_COUNTDOWN_SECONDS`

## Blizzard_DeprecatedCombatLog

- Functions: `CombatLog_Object_IsA`, `CombatLogAddFilter`, `CombatLogClearEntries`, `CombatLogGetCurrentEntry`, `CombatLogGetCurrentEventInfo`, `CombatLogGetNumEntries`, `CombatLogGetRetentionTime`, `CombatLogResetFilter`, `CombatLogSetRetentionTime`, `CombatLogShowCurrentEntry`, `CombatTextSetActiveUnit`, `GetCurrentCombatTextEventInfo`, `DeathRecap_GetEvents`, `DeathRecap_HasEvents`, `GetDeathRecapLink`, `Blizzard_CombatLog_BitToBraceCode`, `CombatLog_Color_ColorArrayByEventType`, `CombatLog_Color_ColorArrayBySchool`, `CombatLog_Color_ColorArrayByUnitType`, `CombatLog_Color_HighlightColorArray`, `CombatLog_String_DamageResultString`, `CombatLog_String_GetIcon`, `CombatLog_String_PowerType`, `CombatLog_String_SchoolString`, `CombatLog_Color_FloatToText`, `CombatLog_Color_ColorStringByEventType`, `CombatLog_Color_ColorStringBySchool`, `CombatLog_Color_ColorStringByUnitType`
- Constants: `COMBATLOG_OBJECT_AFFILIATION_MINE`, `COMBATLOG_OBJECT_AFFILIATION_PARTY`, `COMBATLOG_OBJECT_AFFILIATION_RAID`, `COMBATLOG_OBJECT_AFFILIATION_OUTSIDER`, `COMBATLOG_OBJECT_REACTION_FRIENDLY`, `COMBATLOG_OBJECT_REACTION_NEUTRAL`, `COMBATLOG_OBJECT_REACTION_HOSTILE`, `COMBATLOG_OBJECT_CONTROL_PLAYER`, `COMBATLOG_OBJECT_CONTROL_NPC`, `COMBATLOG_OBJECT_TYPE_PLAYER`, `COMBATLOG_OBJECT_TYPE_NPC`, `COMBATLOG_OBJECT_TYPE_PET`, `COMBATLOG_OBJECT_TYPE_GUARDIAN`, `COMBATLOG_OBJECT_TYPE_OBJECT`, `COMBATLOG_OBJECT_TARGET`, `COMBATLOG_OBJECT_FOCUS`, `COMBATLOG_OBJECT_MAINTANK`, `COMBATLOG_OBJECT_MAINASSIST`, `COMBATLOG_OBJECT_NONE`, `COMBATLOG_OBJECT_AFFILIATION_MASK`, `COMBATLOG_OBJECT_REACTION_MASK`, `COMBATLOG_OBJECT_CONTROL_MASK`, `COMBATLOG_OBJECT_TYPE_MASK`, `COMBATLOG_OBJECT_SPECIAL_MASK`, `COMBATLOG_OBJECT_RAIDTARGET1`, `COMBATLOG_OBJECT_RAIDTARGET2`, `COMBATLOG_OBJECT_RAIDTARGET3`, `COMBATLOG_OBJECT_RAIDTARGET4`, `COMBATLOG_OBJECT_RAIDTARGET5`, `COMBATLOG_OBJECT_RAIDTARGET6`, `COMBATLOG_OBJECT_RAIDTARGET7`, `COMBATLOG_OBJECT_RAIDTARGET8`, `COMBATLOG_OBJECT_RAID_NONE`, `COMBATLOG_OBJECT_RAIDTARGET_MASK`, `COMBATLOG_OBJECT_RAID_MASK`, `AURA_TYPE_BUFF`, `AURA_TYPE_DEBUFF`, `COMBATLOG_HIGHLIGHT_MULTIPLIER`, `COMBATLOG_ICON_RAIDTARGET1`, `COMBATLOG_ICON_RAIDTARGET2`, `COMBATLOG_ICON_RAIDTARGET3`, `COMBATLOG_ICON_RAIDTARGET4`, `COMBATLOG_ICON_RAIDTARGET5`, `COMBATLOG_ICON_RAIDTARGET6`, `COMBATLOG_ICON_RAIDTARGET7`, `COMBATLOG_ICON_RAIDTARGET8`

## Blizzard_DeprecatedCurrencyScript

- `GetCoinIcon`, `GetCoinText`, `GetCoinTextureString`

## Blizzard_DeprecatedGlue

- `IsOnGlueScreen`

## Blizzard_DeprecatedGuildScript

- `GuildInvite`, `GuildUninvite`, `GuildPromote`, `GuildDemote`, `GuildSetLeader`, `GuildSetMOTD`, `GuildLeave`, `GuildDisband`, `GetGuildRosterMOTD`, `GetGuildInfoText`, `SetGuildInfoText`

## Blizzard_DeprecatedHousingCatalog

- `Enum.HousingCatalogEntrySubtype`, `C_HousingCatalog.GetCatalogEntryInfoByRecordID`, `C_HousingCatalog.GetCatalogEntryInfoByItem`, `C_HousingCatalog.GetCatalogEntryInfo`, `C_HousingCatalog.CanDestroyEntry`, `C_HousingCatalog.DestroyEntry`, `C_HousingCatalog.GetFeaturedDecor`, `C_HousingCatalog.GetCatalogCategoryInfo`, `C_HousingCatalog.GetCatalogSubcategoryInfo`, `C_HousingCatalog.SearchCatalogCategories`, `C_HousingCatalog.SearchCatalogSubcategories`, `C_HousingBasicMode.StartPlacingNewDecor`, `C_HousingCatalog.CreateCatalogSearcher`

## Blizzard_DeprecatedInstanceEncounter

- `IsEncounterInProgress`, `IsEncounterSuppressingRelease`, `IsEncounterLimitingResurrections`

## Blizzard_DeprecatedItemScript

- `GetItemQualityColor`, `GetItemInfoInstant`, `GetItemSetInfo`, `GetItemChildInfo`, `DoesItemContainSpec`, `GetItemGem`, `GetItemCreationContext`, `GetItemIcon`, `GetItemFamily`, `GetItemSpell`, `IsArtifactPowerItem`, `IsCurrentItem`, `IsUsableItem`, `IsHelpfulItem`, `IsHarmfulItem`, `IsConsumableItem`, `IsEquippableItem`, `IsEquippedItem`, `IsEquippedItemType`, `ItemHasRange`, `IsItemInRange`, `GetItemClassInfo`, `GetItemInventorySlotInfo`, `BindEnchant`, `ActionBindsItem`, `ReplaceEnchant`, `ReplaceTradeEnchant`, `ConfirmBindOnUse`, `ConfirmOnUse`, `ConfirmNoRefundOnUse`, `DropItemOnUnit`, `EndBoundTradeable`, `EndRefund`, `GetItemInfo`, `GetDetailedItemLevelInfo`, `GetItemSpecInfo`, `GetItemUniqueness`, `GetItemCount`, `PickupItem`, `GetItemSubClassInfo`, `UseItemByName`, `EquipItemByName`, `ReplaceTradeskillEnchant`, `GetItemCooldown`, `IsCorruptedItem`, `IsCosmeticItem`, `IsDressableItem`

## Blizzard_DeprecatedItemSocketInfo

- `CloseSocketInfo`, `GetSocketItemInfo`, `GetNumSockets`, `GetExistingSocketInfo`, `GetExistingSocketLink`, `GetNewSocketInfo`, `GetNewSocketLink`, `ClickSocketButton`, `AcceptSockets`, `GetSocketTypes`, `GetSocketItemRefundable`, `GetSocketItemBoundTradeable`, `HasBoundGemProposed`

## Blizzard_DeprecatedLFG

- `C_LFGInfo.IsPremadeGroupEnabled`, `C_LFGList.GetSearchResultMemberInfo`

## Blizzard_DeprecatedPartyInfo

- `ConfirmReadyCheck`, `DemoteAssistant`, `DoReadyCheck`, `PromoteToAssistant`, `PromoteToLeader`, `SetEveryoneIsAssistant`, `UninviteUnit`, `IsGUIDInGroup`

## Blizzard_DeprecatedPetInfo

- `PetAssistMode`, `GetPetTalentTree`

## Blizzard_DeprecatedPvpScript

- `IsSubZonePVPPOI`, `GetZonePVPInfo`, `TogglePVP`, `SetPVP`

## Blizzard_DeprecatedSoundScript

- `PlayVocalErrorSoundID`

## Blizzard_DeprecatedSpecialization

- Functions: `SetActiveTalentGroup`, `GetTalentTabInfo`, `GetPrimaryTalentTree`, `GetActiveTalentGroup`, `GetTalentTreeMasterySpells`, `GetTalentInfo`, `GetNumSpecializationsForClassID`, `GetSpecializationInfo`, `GetSpecialization`, `GetActiveSpecGroup`, `GetSpecializationMasterySpells`
- Constants: `MAX_TALENT_TIERS`, `NUM_TALENT_COLUMNS`

## Blizzard_DeprecatedSpellBook

- Functions: `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `FindFlyoutSlotBySpellID`, `FindSpellOverrideByID`, `FindBaseSpellByID`
- Constants: `HUNTER_DISMISS_PET`

## Blizzard_DeprecatedSpellScript

- `TargetSpellReplacesBonusTree`, `GetMaxSpellStartRecoveryOffset`, `GetSpellQueueWindow`, `GetSchoolString`, `SpellIsPriorityAura`, `SpellIsSelfBuff`, `SpellGetVisibilityInfo`, `C_Spell.GetSpellLossOfControlCooldown`

## Blizzard_DeprecatedTradeInfo

- `PickupTradeMoney`

## Blizzard_DeprecatedUnitScript

- `CastingInfo`, `ChannelInfo`, `ShowBossFrameWhenUninteractable`

## Blizzard_DeprecatedWorldElapsedTimerTypes

- `LE_WORLD_ELAPSED_TIMER_TYPE_NONE`, `LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE`, `LE_WORLD_ELAPSED_TIMER_TYPE_PROVING_GROUND`
