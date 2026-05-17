# Deprecated Blizzard APIs (12.0.5)

Do not use the functions, constants, aliases, or mixins listed below. They are backward-compatibility shims and may be removed. Use the modern replacement shown in Blizzard source, typically a `C_*` namespace method or mixin method:

https://github.com/Gethe/wow-ui-source/tree/12.0.5/Interface/AddOns

Check the `Blizzard_Deprecated*` folders when choosing the replacement.

## Blizzard_Deprecated

- `GetBattlefieldScore`, `GetBattlefieldStatData`, `UnitIsSpellTarget`, `C_SpellBook.GetSpellBookItemLossOfControlCooldown`

## Blizzard_DeprecatedChatInfo

- Constants: `CHAT_BUTTON_FLASH_TIME`, `CHAT_TELL_ALERT_TIME`, `MAX_COMMUNITY_NAME_LENGTH`, `MAX_COMMUNITY_NAME_LENGTH_NO_CHANNEL`, `MAX_REMEMBERED_TELLS`, `MESSAGE_SCROLLBUTTON_INITIAL_DELAY`, `MESSAGE_SCROLLBUTTON_SCROLL_DELAY`, `MAX_WOW_CHAT_CHANNELS`, `MAX_CHARACTER_NAME_BYTES`, `NUM_CHAT_WINDOWS`, `MAX_COUNTDOWN_SECONDS`
- ChatFrameUtil aliases: `Chat_AddSystemMessage`, `Chat_GetChannelColor`, `Chat_GetChannelShortcutName`, `Chat_GetChatCategory`, `Chat_GetChatFrame`, `Chat_GetColoredChatName`, `Chat_GetCommunitiesChannel`, `Chat_GetCommunitiesChannelColor`, `Chat_GetCommunitiesChannelName`, `Chat_ShouldColorChatByClass`, `ChatEdit_ActivateChat`, `ChatEdit_ChooseBoxForSend`, `ChatEdit_DeactivateChat`, `ChatEdit_FocusActiveWindow`, `ChatEdit_GetActiveChatType`, `ChatEdit_GetActiveWindow`, `ChatEdit_GetLastActiveWindow`, `ChatEdit_GetLastTellTarget`, `ChatEdit_GetLastToldTarget`, `ChatEdit_GetNextTellTarget`, `ChatEdit_HasStickyFocus`, `ChatEdit_InsertLink`, `ChatEdit_LinkItem`, `ChatEdit_SetLastActiveWindow`, `ChatEdit_SetLastTellTarget`, `ChatEdit_SetLastToldTarget`, `ChatEdit_TryInsertChatLink`, `ChatEdit_TryInsertQuestLinkForQuestID`, `ChatFrame_AddCommunitiesChannel`, `ChatFrame_AddMessageEventFilter`, `ChatFrame_CanAddChannel`, `ChatFrame_CanChatGroupPerformExpressionExpansion`, `ChatFrame_ChatPageDown`, `ChatFrame_ChatPageUp`, `ChatFrame_ClearChatFocusOverride`, `ChatFrame_DisplayChatHelp`, `ChatFrame_DisplayGameTime`, `ChatFrame_DisplayGMOTD`, `ChatFrame_DisplayHelpText`, `ChatFrame_DisplayHelpTextSimple`, `ChatFrame_DisplayMacroHelpText`, `ChatFrame_DisplaySystemMessage`, `ChatFrame_DisplaySystemMessageInCurrent`, `ChatFrame_DisplaySystemMessageInPrimary`, `ChatFrame_DisplayTimePlayed`, `ChatFrame_DisplayUsageError`, `ChatFrame_GetChatFocusOverride`, `ChatFrame_GetCommunitiesChannelLocalID`, `ChatFrame_GetCommunityAndStreamFromChannel`, `ChatFrame_GetCommunityAndStreamName`, `ChatFrame_GetFullChannelInfo`, `ChatFrame_GetMobileEmbeddedTexture`, `ChatFrame_OpenChat`, `ChatFrame_RemoveCommunitiesChannel`, `ChatFrame_RemoveMessageEventFilter`, `ChatFrame_ReplyTell`, `ChatFrame_ReplyTell2`, `ChatFrame_ResolveChannelName`, `ChatFrame_ResolvePrefixedChannelName`, `ChatFrame_ScrollDown`, `ChatFrame_ScrollToBottom`, `ChatFrame_ScrollUp`, `ChatFrame_SendTell`, `ChatFrame_SendTellWithMessage`, `ChatFrame_SetChatFocusOverride`, `ChatFrame_TimeBreakDown`, `ChatFrame_TruncateToMaxLength`, `ChatFrame_UpdateChatFrames`, `GetChatTimestampFormat`, `SubstituteChatMessageBeforeSend`
- ChatFrameMixin aliases: `ChatFrame_AddMessage`, `ChatFrame_AddMessageGroup`, `ChatFrame_AddPrivateMessageTarget`, `ChatFrame_AddSingleMessageType`, `ChatFrame_ContainsChannel`, `ChatFrame_ContainsMessageGroup`, `ChatFrame_ExcludePrivateMessageTarget`, `ChatFrame_GetDefaultChatTarget`, `ChatFrame_ReceiveAllPrivateMessages`, `ChatFrame_RegisterForChannels`, `ChatFrame_RegisterForMessages`, `ChatFrame_RemoveAllChannels`, `ChatFrame_RemoveAllMessageGroups`, `ChatFrame_RemoveChannel`, `ChatFrame_RemoveExcludePrivateMessageTarget`, `ChatFrame_RemoveMessageGroup`, `ChatFrame_RemovePrivateMessageTarget`, `ChatFrame_UnregisterAllMessageGroups`, `ChatFrame_UpdateColorByID`, `ChatFrame_UpdateDefaultChatTarget`
- ChatFrameEditBoxMixin aliases: `ChatEdit_AddHistory`, `ChatEdit_ClearChat`, `ChatEdit_DoesCurrentChannelTargetMatch`, `ChatEdit_ExtractChannel`, `ChatEdit_ExtractTellTarget`, `ChatEdit_GetChannelTarget`, `ChatEdit_HandleChatType`, `ChatEdit_ParseText`, `ChatEdit_ResetChatType`, `ChatEdit_ResetChatTypeToSticky`, `ChatEdit_SendText`, `ChatEdit_SetDeactivated`, `ChatEdit_UpdateHeader`
- API: `SendChatMessage`, `DoEmote`, `CancelEmote`

## Blizzard_DeprecatedInstanceEncounter

- `IsEncounterInProgress`, `IsEncounterSuppressingRelease`, `IsEncounterLimitingResurrections`

## Blizzard_DeprecatedItemScript

- `GetItemQualityColor`, `GetItemInfoInstant`, `GetItemSetInfo`, `GetItemChildInfo`, `DoesItemContainSpec`, `GetItemGem`, `GetItemCreationContext`, `GetItemIcon`, `GetItemFamily`, `GetItemSpell`, `IsArtifactPowerItem`, `IsCurrentItem`, `IsUsableItem`, `IsHelpfulItem`, `IsHarmfulItem`, `IsConsumableItem`, `IsEquippableItem`, `IsEquippedItem`, `IsEquippedItemType`, `ItemHasRange`, `IsItemInRange`, `GetItemClassInfo`, `GetItemInventorySlotInfo`, `BindEnchant`, `ActionBindsItem`, `ReplaceEnchant`, `ReplaceTradeEnchant`, `ConfirmBindOnUse`, `ConfirmOnUse`, `ConfirmNoRefundOnUse`, `DropItemOnUnit`, `EndBoundTradeable`, `EndRefund`, `GetItemInfo`, `GetDetailedItemLevelInfo`, `GetItemSpecInfo`, `GetItemUniqueness`, `GetItemCount`, `PickupItem`, `GetItemSubClassInfo`, `UseItemByName`, `EquipItemByName`, `ReplaceTradeskillEnchant`, `GetItemCooldown`, `IsCorruptedItem`, `IsCosmeticItem`, `IsDressableItem`

## Blizzard_DeprecatedPvpScript

- `IsSubZonePVPPOI`, `GetZonePVPInfo`, `TogglePVP`, `SetPVP`

## Blizzard_DeprecatedSpecialization

- Standard: `GetNumSpecializationsForClassID`, `GetSpecializationInfo`, `GetSpecialization`, `GetActiveSpecGroup`, `GetSpecializationMasterySpells`, `GetTalentInfo`
- Classic: `SetActiveTalentGroup`, `GetTalentTabInfo`, `GetPrimaryTalentTree`, `GetActiveTalentGroup`, `GetTalentTreeMasterySpells`
- Constants: `MAX_TALENT_TIERS`, `NUM_TALENT_COLUMNS`

## Blizzard_DeprecatedSpellBook

- `HUNTER_DISMISS_PET`, `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `FindFlyoutSlotBySpellID`, `FindSpellOverrideByID`, `FindBaseSpellByID`

## Blizzard_DeprecatedSpellScript

- `TargetSpellReplacesBonusTree`, `GetMaxSpellStartRecoveryOffset`, `GetSpellQueueWindow`, `GetSchoolString`, `SpellIsPriorityAura`, `SpellIsSelfBuff`, `SpellGetVisibilityInfo`, `C_Spell.GetSpellLossOfControlCooldown`
