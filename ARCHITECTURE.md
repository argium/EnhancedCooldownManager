# ECM Architecture

EnhancedCooldownManager is an event-driven WoW addon built on AceAddon-3.0 / AceDB-3.0.
`Runtime.lua` is the central dispatcher: it registers WoW events, manages layout coalescing, lays out `ExtraIcons` first when it widens the main viewer, and then iterates the chained bar modules. `PowerBar`, `ResourceBar`, and `RuneBar` use `BarMixin.AddBarMixin()`. `BuffBars`, `ExternalBars`, and `ExtraIcons` use `BarMixin.AddFrameMixin()` and manage their own child content.

## Initialization Chain

Six phases from TOC load through the first rendered frame.

```mermaid
flowchart TD
    subgraph LOAD["Phase 1 · Addon Load"]
        TOC["TOC loads files in order:<br/>Constants → Locales → Defaults<br/>→ ClassUtil → ColorUtil → FrameUtil<br/>→ SpellColors → Migration → ImportExport<br/>→ BarMixin → ECM → Runtime → Dialogs<br/>→ Modules → UI files"]
    end

    subgraph INIT["Phase 2 · OnInitialize (ECM.lua)"]
        ECM_INIT["ECM:OnInitialize()"]
        MIG_PREP["Migration.PrepareDatabase()"]
        MIG_RUN["Migration.Run(profile)"]
        ACE_DB["AceDB-3.0:New()"]
        SLASH["Register /ecm slash commands"]
        ECM_INIT --> MIG_PREP --> MIG_RUN --> ACE_DB --> SLASH
    end

    subgraph MOD_INIT["Phase 3 · Module OnInitialize"]
        PB_INIT["PowerBar:OnInitialize()<br/>BarMixin.AddBarMixin(self)"]
        RB_INIT["ResourceBar:OnInitialize()<br/>BarMixin.AddBarMixin(self)"]
        RUNE_INIT["RuneBar:OnInitialize()<br/>BarMixin.AddBarMixin(self)"]
        BB_INIT["BuffBars:OnInitialize()<br/>BarMixin.AddFrameMixin(self)"]
        EB_INIT["ExternalBars:OnInitialize()<br/>BarMixin.AddFrameMixin(self)"]
        II_INIT["ExtraIcons:OnInitialize()<br/>BarMixin.AddFrameMixin(self)"]
    end

    subgraph ENABLE["Phase 4 · OnEnable → Runtime.Enable"]
        ECM_EN["ECM:OnEnable()"]
        RT_EN["Runtime.Enable(addon)"]
        PROF_CB["Register AceDB profile callbacks<br/>OnProfileChanged / Copied / Reset"]

        subgraph MOD_EN["For each MODULE_ORDER"]
            direction LR
            CHECK{"moduleConfig.enabled<br/>≠ false?"}
            DO_EN["addon:EnableModule()"]
            DO_DIS["addon:DisableModule()"]
            CHECK -->|yes| DO_EN
            CHECK -->|no| DO_DIS
        end

        LAYOUT_EV["enableLayoutEvents(addon)<br/>Register 14 WoW events + CVAR_UPDATE<br/>Start watchdog ticker (0.5s)"]

        ECM_EN --> RT_EN --> MOD_EN --> LAYOUT_EV
        ECM_EN --> PROF_CB
    end

    subgraph MOD_ENABLE["Phase 5 · Module OnEnable (each)"]
        ENSURE["self:EnsureFrame()<br/>Creates InnerFrame"]
        REG_FRAME["Runtime.RegisterFrame(self)<br/>→ _modules[name] = self"]
        REG_EVENTS["Register module-specific events<br/>(UNIT_POWER_UPDATE, etc.)"]
        HOOK_BB["BuffBars: C_Timer.After(0.1)<br/>→ HookViewer() + RequestLayout"]
        HOOK_EB["ExternalBars: C_Timer.After(0.1)<br/>→ HookViewer() + UpdateAuras + RequestLayout"]
        ENSURE --> REG_FRAME --> REG_EVENTS
        REG_EVENTS -.->|BuffBars only| HOOK_BB
        REG_FRAME -.->|ExternalBars only| HOOK_EB
    end

    subgraph FIRST["Phase 6 · First Layout"]
        REQ["RequestLayout('ModuleInit')"]
        EXEC["executeLayout()"]
        FADE["updateFadeAndHiddenStates()"]
        ALL_LAY["updateAllLayouts()<br/>→ each module:UpdateLayout()"]
        REQ -->|"C_Timer.After(0)"| EXEC --> FADE --> ALL_LAY
    end

    LOAD --> INIT --> MOD_INIT --> ENABLE --> MOD_ENABLE --> FIRST

    style LOAD fill:#1a1a2e,stroke:#4cc9f0,color:#e0e0e0
    style INIT fill:#1a1a2e,stroke:#f7a855,color:#e0e0e0
    style MOD_INIT fill:#1a1a2e,stroke:#7a84f7,color:#e0e0e0
    style ENABLE fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
    style MOD_ENABLE fill:#1a1a2e,stroke:#a855f7,color:#e0e0e0
    style FIRST fill:#1a1a2e,stroke:#f43f5e,color:#e0e0e0
```

## Event Flow & Layout Pipeline

WoW events funnel through `Runtime.lua` into one of three layout-request paths, all converging on `executeLayout()`.

```mermaid
flowchart TD
    subgraph EVENTS["WoW Event Sources"]
        WOW_MOUNT["PLAYER_MOUNT_DISPLAY_CHANGED<br/>UNIT_ENTERED/EXITED_VEHICLE"]
        WOW_COMBAT["PLAYER_REGEN_ENABLED (delay 0.1s)<br/>PLAYER_REGEN_DISABLED (immediate)"]
        WOW_ZONE["ZONE_CHANGED_* (delay 0.1s)<br/>PLAYER_ENTERING_WORLD (delay 0.4s)"]
        WOW_SPEC["PLAYER_SPECIALIZATION_CHANGED<br/>UPDATE_SHAPESHIFT_FORM"]
        WOW_TARGET["PLAYER_TARGET_CHANGED"]
        WOW_CVAR["CVAR_UPDATE"]
        WOW_REST["PLAYER_UPDATE_RESTING"]
    end

    subgraph MODULE_EVENTS["Module-Specific Events"]
        PB_PWR["UNIT_POWER_UPDATE<br/>→ PowerBar handler"]
        RB_AURA["UNIT_AURA / UNIT_POWER_UPDATE<br/>→ ResourceBar handler"]
        BB_ZONE["ZONE_CHANGED_* / PLAYER_ENTERING_WORLD<br/>→ BuffBars:OnZoneChanged"]
    end

    subgraph HOOKS["Frame Hooks (BuffBars / ExternalBars)"]
        BB_SETPT["child:SetPoint hook<br/>→ restore anchors + restyle"]
        BB_SHOW["child:OnShow hook<br/>→ restyle"]
        BB_HIDE["child:OnHide hook"]
        BB_VIEWER["viewer:OnShow / OnSizeChanged"]
        EB_VIEWER["ExternalDefensivesFrame:UpdateAuras / OnShow / OnHide<br/>→ ExternalBars sync + RequestLayout"]
    end

    subgraph RUNTIME["Runtime.lua — Event Dispatch"]
        HANDLE["handleLayoutEvent(event)"]
        CVAR_HANDLE["CVAR_UPDATE handler<br/>(cooldownViewerEnabled only)"]

        subgraph LAYOUT_PATHS["Three Layout Request Paths"]
            direction LR
            REQ_LAY["RequestLayout(reason)<br/>Coalesce within frame<br/>C_Timer.After(0, exec)"]
            SCHED["ScheduleLayoutUpdate(delay)<br/>Debounced, cancels prior<br/>C_Timer.NewTimer(delay, exec)"]
            IMMED["UpdateLayoutImmediately()<br/>Synchronous execution<br/>(Edit Mode drag)"]
        end

        EXEC_LAY["executeLayout(reason)"]
    end

    subgraph EXECUTE["executeLayout — Common Endpoint"]
        HOOK_CVS["hookCooldownViewerSettings()<br/>(one-time)"]
        UPD_FADE["updateFadeAndHiddenStates()"]
        UPD_ALL["updateAllLayouts(reason)"]

        HOOK_CVS --> UPD_FADE --> UPD_ALL
    end

    subgraph FADE_LOGIC["updateFadeAndHiddenStates()"]
        EDIT_CHK{"Edit Mode<br/>or Preview?"}
        HIDE_CHK["Check: CVar off?<br/>Mounted? Resting OOC?"]
        ALPHA_CHK["Check fade config:<br/>OOC fade + exceptions<br/>(instance, hostile, friendly)"]
        SET_HIDDEN["setGloballyHidden(hidden)<br/>→ each module:SetHidden()"]
        SET_ALPHA["setAlpha(alpha)<br/>→ each module.InnerFrame"]
        ENFORCE["enforceBlizzardFrameState()<br/>→ show/hide/alpha Blizzard frames"]

        EDIT_CHK -->|yes| SET_HIDDEN
        EDIT_CHK -->|no| HIDE_CHK --> ALPHA_CHK --> SET_HIDDEN --> SET_ALPHA --> ENFORCE
    end

    subgraph UPDATE_ALL["updateAllLayouts(reason)"]
        INV_DET["invalidateDetachedAnchorMetrics()"]
        UPD_DET["updateDetachedAnchorLayout()"]
        EXTRA_FIRST["ExtraIcons:UpdateLayout(reason)<br/>first, so the main viewer width is final"]
        CHAIN_LOOP["For each module in CHAIN_ORDER:<br/>PowerBar → ResourceBar → RuneBar<br/>→ BuffBars → ExternalBars"]
        OTHER_LOOP["Remaining non-chain modules (if any)"]
        MOD_UPD["module:UpdateLayout(reason)"]

        INV_DET --> UPD_DET --> EXTRA_FIRST --> CHAIN_LOOP --> OTHER_LOOP --> MOD_UPD
    end

    %% Event Sources → Runtime
    WOW_MOUNT & WOW_COMBAT & WOW_ZONE & WOW_SPEC & WOW_TARGET & WOW_REST --> HANDLE
    WOW_CVAR --> CVAR_HANDLE --> SCHED
    HANDLE -->|"delay > 0"| SCHED
    HANDLE -->|"delay = 0"| UPD_FADE

    %% Module events → RequestLayout
    PB_PWR & RB_AURA & BB_ZONE --> REQ_LAY

    %% Hooks → RequestLayout
    BB_SETPT & BB_SHOW & BB_HIDE & BB_VIEWER & EB_VIEWER --> REQ_LAY

    %% All paths → executeLayout
    REQ_LAY --> EXEC_LAY
    SCHED --> EXEC_LAY
    IMMED --> EXEC_LAY

    EXEC_LAY --> EXECUTE
    UPD_FADE --> FADE_LOGIC
    UPD_ALL --> UPDATE_ALL

    style EVENTS fill:#1a1a2e,stroke:#4cc9f0,color:#e0e0e0
    style MODULE_EVENTS fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
    style HOOKS fill:#1a1a2e,stroke:#f7a855,color:#e0e0e0
    style RUNTIME fill:#16213e,stroke:#7a84f7,color:#e0e0e0
    style EXECUTE fill:#1a1a2e,stroke:#f43f5e,color:#e0e0e0
    style FADE_LOGIC fill:#1a1a2e,stroke:#a855f7,color:#e0e0e0
    style UPDATE_ALL fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
```

## Secondary Flows

### Profile Change

When a user switches, copies, or resets a profile, AceDB fires a callback → `ECM:OnProfileChangedHandler()` → re-runs migration → `Runtime.Enable()` re-enables/disables modules per new config → schedules a full layout with reason `"ProfileChanged"`. BuffBars and ExternalBars clear their scoped SpellColors discovered-key caches on this reason.

### Edit Mode

LibEditMode detects WoW's Edit Mode enter/exit. On enter, all modules are forced visible (alpha 1, not hidden). Dragging or resizing calls `UpdateLayoutImmediately()` for instant feedback. On exit, normal fade/hidden rules re-apply.

### Options UI

Setting changes flow through LibSettingsBuilder's `onChange` → `Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")`.
The embedded library is loaded through `Libs/LibSettingsBuilder/embed.xml`, which guarantees `Core.lua`, the primitive helper modules, standard control modules, composite control modules, and `Utility.lua` initialize in order before options pages register.

Options pages now use LibSettingsBuilder as a single declarative registration tree:

- `SB.GetRoot(L["ADDON_NAME"])` returns the singleton root handle,
- each options page has a dedicated `UI/*Options.lua` or `UI/*Page.lua` owner (`UI/AboutOptions.lua`, `UI/AdvancedOptions.lua`, `UI/SpellColorsPage.lua`, etc.) that exports plain section/page spec tables instead of registering itself,
- `UI/Options.lua` owns only the root SettingsBuilder assembly and calls `root:Register({ page = ns.AboutPage, sections = { ... } })` once,
- `root:Register(...)` materializes the tree into Blizzard Settings (flattening single-page sections by default and nesting multi-page sections automatically),
- dynamic pages keep a registered page handle through `onRegistered(page)` and refresh via `page:Refresh()` when async or transient state changes.

`UI/SpellColorsPage.lua` now owns the shared Spell Colors subcategory. `BuffBarsOptions` registers the page once, and both `BuffBars` and `ExternalBars` register scoped sections into it, so the two modules share one editor without sharing saved color pools.

LibSettingsBuilder v2 Phase 1 also freezes the intended replacement surface without switching ECM over to it yet:

- target factory: `LSB.New(config)`
- target runtime lookups: `lsb:GetSection(...)`, `lsb:GetRootPage()`, `lsb:GetPage(...)`, `lsb:HasCategory(...)`
- target page handle API: `page:GetId()`, `page:Refresh()`
- deprecated compatibility namespace: `LSBDeprecated`

Phase 2 then makes raw declarative row tables the canonical registration schema and removes builder-level row helper constructors from the public `lsb` surface. ECM continues to register through plain row tables.

Deprecated non-declarative page-construction APIs were removed from the builder surface. ECM settings pages are registered through the root tree only.

Pages still use the same canonical row types:

- standard persisted controls (`checkbox`, `slider`, `dropdown`, `color`, `input`) bind through path mode or handler mode,
- layout rows (`header`, `subheader`, `info`, `button`, `pageActions`, `canvas`) handle structure and copy,
- dynamic editors use `list` and `sectionList` rows with library-owned rendering,
- `canvas` rows stay on the existing lifecycle path so page switches do not lose or misplace embedded content.

### Watchdog Ticker

A 0.5s `C_Timer.NewTicker` handles deferred Blizzard frame hooking (stops retrying once setup completes), enforces hidden/alpha state against Blizzard re-shows, and syncs module alpha.

### External Bars / `ExternalDefensivesFrame`

`ExternalBars` is hook-driven rather than event-driven. It mirrors Blizzard's `ExternalDefensivesFrame` instead of scanning auras itself:

1. `OnEnable()` defers `HookViewer()` by `C_Timer.After(0.1)` so the Blizzard frame exists before hooks are attached.
2. `HookViewer()` post-hooks `ExternalDefensivesFrame:UpdateAuras()` and listens to the frame's `OnShow` / `OnHide` transitions.
3. `OnExternalAurasUpdated()` copies `viewer.auraInfo[]` into `_auraStates[]`, enriches accessible spell metadata through `C_UnitAuras.GetAuraDataByAuraInstanceID()`, and requests a layout pass.
4. `UpdateLayout()` maps `_auraStates[]` to pooled child bars, styles each row through `BarStyle.StyleChildBar(...)`, and routes spell-color discovery / lookup through the `ns.SpellColors.Get("externalBars")` store.
5. Bar fill is rendered by a `Cooldown` overlay via `SetCooldownDuration(duration, timeMod)`. Lua only formats duration text when expiration data is safe to inspect directly.
6. `hideOriginalIcons` uses `ExternalDefensivesFrame:SetAlpha(0)` plus `EnableMouse(false)` rather than `Hide()`, so Blizzard keeps driving `UpdateAuras()`.

```mermaid
flowchart TD
    subgraph PROFILE["Profile Change Flow"]
        USER_SWITCH["User switches/copies/resets profile"]
        ACE_CB["AceDB callback fires:<br/>OnProfileChanged / OnProfileCopied / OnProfileReset"]
        PROF_HANDLER["ECM:OnProfileChangedHandler()"]
        MIG["Migration.Run(new profile)"]
        RT_EN2["Runtime.Enable(addon)<br/>→ Re-enable/disable modules per new config"]
        SCHED_PC["ScheduleLayoutUpdate(0, 'ProfileChanged')"]
        SPELL_CLEAR["BuffBars / ExternalBars:UpdateLayout('ProfileChanged')<br/>→ SpellColors.Get(scope):ClearDiscoveredKeys()"]

        USER_SWITCH --> ACE_CB --> PROF_HANDLER --> MIG --> RT_EN2 --> SCHED_PC --> SPELL_CLEAR
    end

    subgraph EDITMODE["Edit Mode Flow"]
        EM_ENTER["User enters WoW Edit Mode"]
        EM_DETECT["LibEditMode callback → 'enter'"]
        EM_LAYOUT["ScheduleLayoutUpdate(0, 'EditModeEnter')"]
        EM_FORCE["updateFadeAndHiddenStates()<br/>→ hidden=false, alpha=1 (always visible)"]

        EM_DRAG["User drags module frame"]
        EM_SAVE["onPositionChanged callback<br/>→ EditMode.SavePosition(config, ...)"]
        EM_IMMED["UpdateLayoutImmediately('EditModeDrag')"]

        EM_SLIDER["User adjusts width/height slider"]
        EM_WRITE["Direct config write: cfg.width = value"]
        EM_IMMED2["UpdateLayoutImmediately('EditModeWidth')"]

        EM_EXIT["User exits Edit Mode"]
        EM_EXIT_LAY["ScheduleLayoutUpdate(0, 'EditModeExit')<br/>→ Re-apply fade/hidden per config"]

        EM_ENTER --> EM_DETECT --> EM_LAYOUT --> EM_FORCE
        EM_DRAG --> EM_SAVE --> EM_IMMED
        EM_SLIDER --> EM_WRITE --> EM_IMMED2
        EM_EXIT --> EM_EXIT_LAY
    end

    subgraph OPTIONS["Options UI Flow"]
        OPT_CHANGE["User toggles setting in Options UI"]
        LSB_CB["LibSettingsBuilder onChange callback"]
        OPT_SCHED["Runtime.ScheduleLayoutUpdate(0, 'OptionsChanged')"]

        OPT_CHANGE --> LSB_CB --> OPT_SCHED
    end

    subgraph WATCHDOG["Watchdog Ticker (0.5s interval)"]
        WD_TICK["Every 0.5 seconds"]
        WD_SETUP{"Setup<br/>complete?"}
        WD_HOOK["hookBlizzardFrames()<br/>hookCooldownViewerSettings()"]
        WD_ENFORCE["enforceBlizzardFrameState()<br/>→ Correct Blizzard re-shows/alpha"]
        WD_ALPHA["Sync module alpha<br/>→ LazySetAlpha per module"]

        WD_TICK --> WD_SETUP
        WD_SETUP -->|no| WD_HOOK --> WD_ENFORCE
        WD_SETUP -->|yes| WD_ENFORCE --> WD_ALPHA
    end

    style PROFILE fill:#1a1a2e,stroke:#f7a855,color:#e0e0e0
    style EDITMODE fill:#1a1a2e,stroke:#7a84f7,color:#e0e0e0
    style OPTIONS fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
    style WATCHDOG fill:#1a1a2e,stroke:#f43f5e,color:#e0e0e0
```

## Event Reference

Runtime registers the shared layout events; modules register their own data-driven events in `OnEnable`. Events with multiple registrants are intentional — Runtime handles visibility/positioning while the module handles its own data refresh.

`ExternalBars` is intentionally absent from this table: it mirrors `ExternalDefensivesFrame` through hooks rather than registering its own aura event stream.

| Event | Registrant(s) | Purpose |
|-------|---------------|---------|
| CVAR_UPDATE | Runtime | Schedules layout when `cooldownViewerEnabled` changes |
| PLAYER_ENTERING_WORLD | Runtime, BuffBars, ExtraIcons | Runtime: full layout; BuffBars: refresh zone buffs; ExtraIcons: full refresh |
| PLAYER_MOUNT_DISPLAY_CHANGED | Runtime | Immediate layout for mounted-state visibility |
| PLAYER_REGEN_DISABLED | Runtime | Immediate layout; sets `_inCombat` flag |
| PLAYER_REGEN_ENABLED | Runtime | Delayed layout (combat-end delay); clears `_inCombat` |
| PLAYER_SPECIALIZATION_CHANGED | Runtime | Immediate layout for spec-dependent module visibility |
| PLAYER_TARGET_CHANGED | Runtime | Immediate layout for target-frame positioning |
| PLAYER_UPDATE_RESTING | Runtime | Immediate layout for resting-state visibility |
| UNIT_ENTERED_VEHICLE | Runtime | Immediate layout to hide bars in vehicle |
| UNIT_EXITED_VEHICLE | Runtime | Immediate layout to restore bars after vehicle |
| UPDATE_SHAPESHIFT_FORM | Runtime | Immediate layout for form/stance changes |
| VEHICLE_UPDATE | Runtime | Immediate layout for vehicle seat changes |
| ZONE_CHANGED | Runtime, BuffBars | Runtime: delayed layout; BuffBars: refresh zone-specific buffs |
| ZONE_CHANGED_INDOORS | Runtime, BuffBars | Runtime: delayed layout; BuffBars: refresh buff data |
| ZONE_CHANGED_NEW_AREA | Runtime, BuffBars | Runtime: delayed layout; BuffBars: refresh area-specific buffs |
| BAG_UPDATE_COOLDOWN | ExtraIcons | Throttled cooldown-state refresh |
| BAG_UPDATE_DELAYED | ExtraIcons | Layout update after bag contents finalize |
| PLAYER_EQUIPMENT_CHANGED | ExtraIcons | Refresh tracked equipment slot cooldowns on gear swap |
| SPELLS_CHANGED | ExtraIcons | Layout update when known spells change (talent/level) |
| SPELL_UPDATE_COOLDOWN | ExtraIcons | Throttled spell cooldown-state refresh |
| RUNE_POWER_UPDATE | RuneBar | Start rune animation ticker; request layout |
| UNIT_AURA | ResourceBar | Layout update when player auras change |
| UNIT_POWER_UPDATE | PowerBar, ResourceBar | PowerBar: primary power bar update; ResourceBar: resource tracking |

## Public Interfaces

### Runtime (`ns.Runtime`)

Central layout dispatcher. All layout requests funnel through here.

| Method | Description |
|--------|-------------|
| `Enable(addon)` | Start event dispatch and watchdog ticker |
| `Disable(addon)` | Stop event dispatch and cancel watchdog |
| `RequestLayout(reason?, opts?)` | Deferred layout pass (coalesces within frame via `C_Timer.After(0)`) |
| `ScheduleLayoutUpdate(delay, reason?)` | Debounced timer layout; later call with shorter delay supersedes |
| `UpdateLayoutImmediately(reason?)` | Synchronous layout (Edit Mode drag/resize) |
| `RequestRefresh(module, reason?)` | Values-only refresh for a single module |
| `RegisterFrame(frame)` | Register a module frame to receive layout updates |
| `UnregisterFrame(frame)` | Unregister a module frame |
| `SetLayoutPreview(active)` | Toggle layout preview mode (bypasses hide/fade) |
| `OnCombatEnd()` | Optional hook called when player exits combat |

### BarMixin (`ns.BarMixin`)

Two mixins applied in `OnInitialize`. `FrameProto` provides positioning, visibility, and Edit Mode support. `BarProto` extends it with StatusBar, ticks, text, and value refresh.

**Setup:**

| Method | Description |
|--------|-------------|
| `AddFrameMixin(target, name)` | Apply frame-only mixin (used by BuffBars, ExternalBars, ExtraIcons) |
| `AddBarMixin(module, name)` | Apply bar mixin: frame + StatusBar + ticks (used by PowerBar, ResourceBar, RuneBar) |

**FrameProto (mixed into every module):**

| Method | Description |
|--------|-------------|
| `EnsureFrame()` | Create InnerFrame and register Edit Mode (call in `OnEnable`) |
| `CreateFrame()` | Build background, status bar, border, text layers |
| `UpdateLayout(why?)` | Full layout pass: position, dimensions, border, background |
| `Refresh(why?, force?)` | Base refresh (override for data updates) |
| `ThrottledRefresh(why?)` | Rate-limited refresh (skips if within `updateFrequency`) |
| `GetModuleConfig()` | Return this module's config from AceDB profile |
| `IsReady()` | Check enabled + has frame + has config |
| `SetHidden(hide)` | Set global hidden state; defers show to next layout |
| `ShouldShow()` | Evaluate whether frame should be visible |
| `GetNextChainAnchor(frameName?, anchorMode?)` | Return anchor frame and `isFirst` flag for chain/detached/free modes |
| `CalculateLayoutParams()` | Calculate layout params for current anchor mode |
| `ApplyFramePosition()` | Apply positioning from layout params |

**BarProto (mixed into PowerBar, ResourceBar, RuneBar):**

| Method | Description |
|--------|-------------|
| `Refresh(why?, force?)` | Update StatusBar value, text, texture, and dimensions |
| `GetStatusBarValues()` | Override to return `(current, max, displayValue, isFraction)` |
| `GetStatusBarColor()` | Override or use default class color |
| `EnsureTicks(count, parentFrame, poolKey?)` | Create/show/hide tick frames from pool |
| `HideAllTicks(poolKey?)` | Hide all ticks in pool |
| `LayoutResourceTicks(maxResources, color?, tickWidth?, poolKey?)` | Position ticks as resource dividers |
| `LayoutValueTicks(statusBar, ticks, maxValue, defaultColor, defaultWidth, poolKey?)` | Position ticks at specific values |

`BarStyle` (`BarStyle.lua`) is a stateless namespace of shared child-bar styling helpers used by both `BuffBars` and `ExternalBars`. It is not a mixin — callers invoke the helpers directly (e.g. `BarStyle.StyleChildBar(...)`) so both modules render through the same icon, background, anchor, and spell-color paths.

**Shared child-bar styling helpers:**

| Method | Description |
|--------|-------------|
| `ApplySquareIconStyle(iconFrame, iconTexture, iconOverlay, debuffBorder)` | Remove Blizzard round-mask / overlay treatment once and keep icons square |
| `StyleBarHeight(frame, bar, iconFrame, config, globalConfig)` | Apply shared row height to the container, status bar, and icon |
| `StyleBarBackground(frame, barBG, config, globalConfig)` | Reparent and restyle the shared bar background texture |
| `StyleBarColor(module, frame, bar, globalConfig, spellColors?, retryCount?)` | Resolve spell colors through a per-scope store with secret-value retry handling |
| `StyleBarIcon(frame, iconFrame, config)` | Show, hide, and align the optional icon region |
| `StyleBarAnchors(frame, bar, iconFrame, config)` | Apply the shared text / icon anchor layout |
| `StyleChildBar(module, frame, config, globalConfig, spellColors?)` | Run the complete shared BuffBars / ExternalBars child-bar styling pass |

### ExternalBars (`Modules/ExternalBars.lua`)

Renders Blizzard external defensive auras as ECM-owned bar rows. `ExternalBars` inherits `FrameProto`, owns a pooled set of child bars, and shares the BuffBars row styling helpers from `BarStyle`.

- **Authoritative source:** `ExternalDefensivesFrame.auraInfo[]` populated by Blizzard `UpdateAuras()`.
- **Viewer hook:** `HookViewer()` post-hooks `UpdateAuras()` and `OnShow` / `OnHide`.
- **Internal state:** `OnExternalAurasUpdated()` copies current aura entries into `_auraStates[]` keyed by Blizzard's aura-array index, not by `auraInstanceID`.
- **Rendering:** `UpdateLayout()` sizes the container, configures pooled child bars, and uses a `Cooldown` overlay per row for the draining fill.
- **Color scope:** spell-color lookup and discovery run through `ns.SpellColors.Get("externalBars")`, so the shared Spell Colors page can manage it independently from BuffBars while the runtime avoids passing scope strings through every call.
- **Original icon suppression:** `hideOriginalIcons` drives `SetAlpha(0)` / `EnableMouse(false)` on `ExternalDefensivesFrame`; it never calls `Hide()`.

### ExtraIcons (`Modules/ExtraIcons.lua`)

Displays cooldown-tracked icons alongside Blizzard's cooldown viewer frames. Uses a dual-viewer architecture with a stack-aware resolver.

**Viewer Registry:** Maps abstract viewer keys to Blizzard frame globals. Current keys: `"utility"` → `UtilityCooldownViewer`, `"main"` → `EssentialCooldownViewer`. Each viewer has its own container frame, on-demand icon pool, and hook set. The main viewer's expanded footprint also drives a shared midpoint offset for the two-viewer layout; utility applies that pair offset first, then layers its own local centering so moving icons between viewers preserves the combined layout.

**Entry Kinds and Resolution:**

| Kind | Config Fields | Resolution | Cooldown Source |
|------|--------------|------------|-----------------|
| `equipSlot` | `slotId` | `GetInventoryItemID` + `C_Item.GetItemSpell` on-use check | `GetInventoryItemCooldown` |
| `item` | `ids[]` (priority stack) | First with `C_Item.GetItemCount > 0` | `C_Item.GetItemCooldown` |
| `spell` | `ids[]` (priority stack) | First known via `C_SpellBook.IsSpellKnown`, then `C_Spell.GetSpellTexture` | `C_Spell.GetSpellCooldown` (pass-through, no inspection) |

Predefined stacks (`BUILTIN_STACKS`) are referenced by `stackKey` in config; the resolver reads `kind`/`ids`/`slotId` from the constant at runtime. Built-in entries may also persist `disabled = true`, which keeps them in the settings list but skips them during runtime resolution. Custom and racial entries store fields directly in saved config.

**Config Structure (`profile.extraIcons`):**

```lua
{
    enabled = true,
    viewers = {
        utility = {                      -- ordered array
            { stackKey = "trinket1" },   -- resolved from BUILTIN_STACKS
            { stackKey = "trinket2", disabled = true },
            { stackKey = "combatPotions" },
            { kind = "spell", ids = { 59752 } },  -- racial (self-contained)
        },
        main = {},
    },
}
```

**Settings UI (`UI/ExtraIconsOptions.lua`):**

Registers through the root/section/page API and exposes only native controls plus the single viewer-management section list. Data helpers (`_addStackKey`, `_removeEntry`, `_reorderEntry`, `_moveEntry`, `_toggleBuiltinRow`, etc.) and page setup hooks (`SetRegisteredPage`, `EnsureItemLoadFrame`, `BuildSections`, `ResetToDefaults`) are exposed on `ns.ExtraIconsOptions` for testability and options bootstrap.

*Row rendering and add flow.* Each viewer renders its ordered rows followed by an inline add row (`[type] [id] [resolved name] [add]`). Draft item IDs resolve asynchronously: pending item loads show `...`, request `GET_ITEM_INFO_RECEIVED`, and refresh the page as soon as Blizzard returns the item data so the resolved name and add button appear without extra typing. Duplicate entries are blocked across both viewers for add and move flows.

*Built-in rows.* Built-in rows use the trailing button as an enable/disable toggle instead of removal, and disabled built-ins are normalized to the bottom of their viewer in `BUILTIN_STACK_ORDER` so they stay visually stable. Missing built-ins are synthesized as disabled placeholders in the utility viewer so older profiles can still re-enable them without a separate quick-add section.

*Trinket and equip-slot filtering.* Trinket built-ins are only rendered when the currently equipped slot resolves to an on-use spell, so passive trinkets stay in saved variables but disappear from the table until they become usable again. Equip-slot placeholders follow the same on-use filter, and trinket-slot equipment changes refresh the page so the visible rows stay in sync.

*Racials.* The current-player racial is synthesized as a disabled placeholder in the utility viewer when absent; racial lookup uses only the `UnitRace("player")` race file token, with no normalization, spellbook, or localized-name fallback. Adding it writes a normal spell entry, and removing it returns the UI to that placeholder state. Racials from other races are filtered out of the settings list even if they remain in saved variables.

*Lifecycle.* Special-row behavior is explained through a short legend plus row-specific tooltips. Section-list rows stay on the current lifecycle path so viewer switches do not lose or misplace embedded content.

### FrameUtil (`ns.FrameUtil`)

Lazy setters avoid redundant frame API calls — they compare the new value against state and only call the Blizzard API when it changed.

| Method | Description |
|--------|-------------|
| `LazySetHeight(frame, h)` | Set height if changed |
| `LazySetWidth(frame, w)` | Set width if changed |
| `LazySetAlpha(frame, alpha)` | Set alpha if changed |
| `LazySetAnchors(frame, anchors)` | Clear and re-apply anchors if changed |
| `LazySetBackgroundColor(frame, color)` | Set background color if changed |
| `LazySetStatusBarTexture(bar, path)` | Set bar texture if changed |
| `LazySetStatusBarColor(bar, r, g, b, a)` | Set bar color if changed |
| `LazySetBorder(frame, borderConfig)` | Set border color/thickness if changed |
| `ApplyFont(fontString, globalConfig, moduleConfig)` | Apply font settings from config |
| `PixelSnap(value)` | Snap floating value to pixel boundary |
| `NormalizePosition(point, relativePoint, x, y, parent?)` | Convert offsets between anchor references |
| `ConvertOffsetToAnchor(src, target, x, y, w?, h?, parent?)` | Convert offsets accounting for frame dimensions |

### SpellColors (`ns.SpellColors`)

Shared multi-tier key system for per-spell color customization on BuffBars and ExternalBars. Keys match across spell name, spell ID, cooldown ID, and texture file ID. Scope-specific state now lives on `ECM_SpellColorStore` instances created by `ns.SpellColors.New(scope, accessor?)` or retrieved from the shared registry via `ns.SpellColors.Get(scope)`, so BuffBars and ExternalBars share lookup logic while keeping separate defaults, saved colors, and discovered-key caches.

| Method | Description |
|--------|-------------|
| `MakeKey(spellName?, spellID?, cooldownID?, textureFileID?)` | Create normalized spell-color key |
| `NormalizeKey(key)` | Normalize key payload into opaque key |
| `KeysMatch(left, right)` | Check if two keys identify the same spell |
| `MergeKeys(base, other)` | Merge identifiers from matching keys |
| `New(scope, accessor?)` | Create an isolated spell-color store (primarily for tests) |
| `Get(scope?)` | Return the shared spell-color store for a scope |

Store methods (`SpellColors.Get(scope):...`):

| Method | Description |
|--------|-------------|
| `GetColorByKey(key)` | Get a custom color for a spell within that store's scope |
| `GetColorForBar(frame)` | Get a custom color for a BuffBars / ExternalBars row |
| `SetColorByKey(key, color)` | Set a custom color for a spell within that store's scope |
| `ResetColorByKey(key)` | Remove a custom color entry |
| `GetAllColorEntries()` | Return deduplicated color entries for the current class/spec in that store's scope |
| `GetDefaultColor()` | Return the default color for the current class/spec in that store's scope |
| `SetDefaultColor(color)` | Set the default color for the current class/spec in that store's scope |
| `ReconcileAllKeys(keys)` | Batch-reconcile keys within that store's scope (propagate most-recent across tiers) |
| `RemoveEntriesByKeys(keys)` | Remove matching persisted and discovered spell-color keys within that store's scope |
| `DiscoverBar(frame)` | Register a discovered bar key within that store's scope |
| `ClearDiscoveredKeys()` | Clear the discovered-key cache for that store's scope |
| `ClearCurrentSpecColors()` | Clear all colors for the current class/spec in that store's scope |
| `_SetConfigAccessor(accessor)` | Private test-only override for swapping the config source after construction |

The spell-color settings page (`UI/SpellColorsPage.lua`) renders one shared multi-section canvas. Each section merges persisted and discovered keys for its own scope, enables `Reconcile` and `Remove Stale` only when a row is still missing one or more identifiers, and lets `Remove Stale` confirmed-delete incomplete entries from both the current-spec stores and the runtime discovered-key cache while echoing each removal to chat.

### SpellColorsPage (`UI/SpellColorsPage.lua`)

Shared settings-page builder for spell colors. BuffBars and ExternalBars both register sections into the same page rather than owning duplicate subcategories.

| Method | Description |
|--------|-------------|
| `RegisterSection(section)` | Register or update a spell-color section (`key`, `label`, `scope`, `isDisabledDelegate`, `ownerModuleName`) |
| `CreateSectionDisabledDelegate(configPath, ownerModuleName)` | Create the disabled predicate used by a section |
| `CreatePage(subcatName)` | Return the shared multi-section page spec used by options registration |
| `SetRegisteredPage(page)` | Cache the live page handle so runtime changes can refresh it |

### ClassUtil (`ns.ClassUtil`)

| Method | Description |
|--------|-------------|
| `GetResourceType(class, specIndex, shapeshiftForm)` | Return resource type enum for given spec |
| `GetPlayerResourceType()` | Return resource type for current player |
| `GetCurrentMaxResourceValues(resourceType)` | Return `(max, current, safeMax)` for resource type |

### ColorUtil (`ns.ColorUtil`)

| Method | Description |
|--------|-------------|
| `AreEqual(c1, c2)` | Compare two color tables for equality |
| `ColorToHex(color)` | Convert color to `"RRGGBB"` hex string |
| `Sparkle(text, startColor?, midColor?, endColor?)` | Apply 3-stop gradient to text |

### ImportExport (`ns.ImportExport`)

| Method | Description |
|--------|-------------|
| `ExportCurrentProfile()` | Export current profile; returns `(exportString, error)` |
| `ValidateImportString(importString)` | Validate without applying; returns `(data, error)` |
| `ApplyImportData(data)` | Apply validated data to current profile |
| `EncodeData(data)` | Low-level encode to compressed string |
| `DecodeData(importString)` | Low-level decode from compressed string |

### Migration (`ns.Migration`)

| Method | Description |
|--------|-------------|
| `Run(profile)` | Run all pending migrations on profile |
| `PrepareDatabase()` | Reseed versioned database slots |
| `Rollback(targetVersion)` | Roll back database to target version |
| `ValidateRollback(targetVersion)` | Validate rollback feasibility |
| `PrintInfo()` | Print schema version to chat |
| `GetLogText()` | Return migration log entries as string |
| `FlushLog()` | Clear migration log buffer |

### OptionUtil (`ns.OptionUtil`)

Shared helpers for the Settings UI, used by all option pages.

| Method | Description |
|--------|-------------|
| `GetNestedValue(tbl, path)` | Get value at dot-separated path |
| `SetNestedValue(tbl, path, value)` | Set value at dot-separated path, creating intermediates |
| `GetCurrentClassSpec()` | Return `(classID, specIndex, className, specName, classEnum)` |
| `GetIsDisabledDelegate(configPath)` | Return closure checking if module is disabled |
| `CreateModuleEnabledHandler(moduleName, requiresReload?)` | Create enable/disable toggle handler |
| `CreateBarRows(isDisabled, options?)` | Generate standard bar layout/appearance rows |
| `CreateDetachedStackRows()` | Generate detached positioning rows |
| `CreateDetachedAnchorEditModeSettings(getGlobalConfig, onChanged)` | Create Edit Mode settings for detached anchor |
| `OpenColorPicker(currentColor, hasOpacity, onChange)` | Open Blizzard color picker |
| `MakeConfirmDialog(text)` | Create confirm dialog for `StaticPopup` |
| `OpenLayoutPage()` | Open settings to the registered Layout page |

### ECM Addon Instance

Top-level namespace utilities and addon methods available globally.

| Method | Description |
|--------|-------------|
| `ns.GetGlobalConfig()` | Return global config section from database |
| `ns.IsDebugEnabled()` | Check if debug mode is enabled |
| `ns.IsDeathKnight()` | Check if player is a Death Knight |
| `ns.ToString(v)` | Convert value to safe string (handles taint) |
| `ns.CloneValue(value)` | Deep-clone a value |
| `ns.Log(module, message, data)` | Log to debug chat and DevTool |
| `mod:GetECMModule(name, silent?)` | Get ECM module by name |
| `mod:ConfirmReloadUI(text, onAccept?, onCancel?)` | Show confirm popup, reload on accept |
| `mod:ShowImportDialog()` | Show import string input dialog |
| `mod:ShowExportDialog(exportString)` | Show export string copy dialog |
| `mod:ShowCopyTextDialog(text, title?)` | Show small text-copy dialog |
| `mod:ShowMigrationLogDialog(text)` | Show scrollable migration log |
| `mod:ShowReleasePopup(force?)` | Show "What's New" popup |
