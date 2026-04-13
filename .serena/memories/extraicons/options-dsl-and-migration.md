# ExtraIcons / Options DSL / SpellColors refresh

## ExtraIcons replaced ItemIcons
- `Modules/ItemIcons.lua` and `UI/ItemIconsOptions.lua` were removed and replaced by `Modules/ExtraIcons.lua` and `UI/ExtraIconsOptions.lua`.
- The profile model changed from boolean flags under `profile.itemIcons` to `profile.extraIcons = { enabled, viewers = { utility = {...}, main = {...} } }`.
- `Constants.EXTRAICONS` maps to config key `extraIcons`; `Constants.MODULE_ORDER` now includes `ExtraIcons`.
- Defaults seed `extraIcons.viewers.utility` with builtin stack entries for `trinket1`, `trinket2`, `combatPotions`, `healthPotions`, and `healthstones`.
- Migration V12 is the frozen conversion from legacy `itemIcons` flags into ordered `extraIcons.viewers.utility` entries and then deletes `profile.itemIcons`.

## Runtime coupling
- `ExtraIcons` is not treated like a purely independent trailing module. `Runtime.updateAllLayouts()` runs `ExtraIcons:UpdateLayout()` before the chained bar modules so width-sensitive bars can anchor against the final widened main-viewer footprint.
- `ExtraIcons:GetMainViewerAnchor()` returns a synthetic anchor frame when the module extends the main Blizzard viewer; otherwise it falls back to the Blizzard frame.
- `ExtraIcons` manages two viewers (`utility`, `main`), tracks icon pools per viewer, hooks viewer/show/size events, and refreshes cooldowns from bag/equipment/spell events.

## ExtraIcons options UI
- `UI/ExtraIconsOptions.lua` is fully data-driven through `LibSettingsBuilder`.
- The central `RegisterSettings(SB)` builds a sectioned `collection` with one section per viewer, each containing action rows (reorder, move between viewers, hide/show builtin row, delete custom row).
- The add-entry flow uses draft state per viewer, a mode-input trailer, duplicate detection, and async item-name refresh via `GET_ITEM_INFO_RECEIVED` + `SB.RefreshCategory(...)`.
- Builtin rows and the current racial ability are represented as special rows instead of separate bespoke controls.

## LibSettingsBuilder expansion
- `Libs/LibSettingsBuilder/LibSettingsBuilder.lua` now supports richer row types and behaviors used across ECM options: `header`, `subheader`, `info`, `input`, `button`, `collection`, embedded canvas rows, sectioned collections, swatch/editor presets, action buttons, and inline slider editing.
- Prefer extending the existing DSL-driven options flow instead of hand-building new settings-frame widgets when working on complex options screens.

## SpellColors / BuffBars options
- `SpellColors.lua` now owns the keyed buff-bar color model. Persisted entries are class/spec-scoped and keyed by name/spellID/cooldownID/texture tiers.
- `SpellColors.GetAllColorEntries()` merges persisted rows with runtime-discovered keys so `UI/BuffBarsOptions.lua` can render active bars without poking into `BuffBars` internals.
- Buff-bar spell colors UI now uses a `collection` with swatch rows plus header actions for reset, reconcile/reload, and stale-entry cleanup.
