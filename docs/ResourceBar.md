# ResourceBar

`ResourceBar` is the chained status-bar module that renders class/spec-specific secondary resources for Retail WoW. It covers standard combo-style resources like combo points, chi, holy power, essence, and soul shards, plus addon-specific tracked resources such as Vengeance soul fragments, Devourer fragment progress, icicles, and Maelstrom Weapon stacks.

## 1. Summary table

| Attribute | Value |
|---|---|
| **Module name** | `ResourceBar` |
| **Description** | Renders a single status bar for the player's current class/spec resource, switching resource type dynamically through `ClassUtil.GetPlayerResourceType()`. It also draws divider ticks for discrete resources and supports alternate capped colors for selected resource types. |
| **Source file** | [`Modules/ResourceBar.lua`](../Modules/ResourceBar.lua) |
| **Mixin** | `BarMixin.AddBarMixin(self, "ResourceBar")` — inherits `BarProto`, which inherits `FrameProto`. `ResourceBar` overrides `ShouldShow()`, `GetStatusBarValues()`, `GetStatusBarColor()`, and `GetTickSpec()` on top of the shared bar/frame lifecycle. |
| **Events listened to** | <ul><li>`UNIT_AURA` — player-only refresh path for aura-backed resources such as icicles, soul fragments, Devourer progress, and Maelstrom Weapon; secret-value-bearing.</li><li>`UNIT_POWER_UPDATE` — player-only refresh path for standard power resources and any resource changes surfaced through the power event; secret-value-bearing.</li></ul> |
| **Dependencies** | <ul><li>`ns.Addon` — owns the Ace module instance via `:NewModule()`.</li><li>`ns.BarMixin` — supplies `BarProto`/`FrameProto` behavior.</li><li>`ns.Runtime` — frame registration plus values-only refresh dispatch.</li><li>`ns.ClassUtil` — resolves active resource type and `(max, current, safeMax)` values.</li><li>`ns.Constants` — resource-type IDs, tick color, and capped-color feature gates.</li></ul> |
| **Options file(s)** | [`UI/ResourceBarOptions.lua`](../UI/ResourceBarOptions.lua) |
| **Options dependencies** | <ul><li>`ns.OptionUtil` — module enabled handler, disabled delegate, and shared bar row generation.</li><li>`ns.Constants` — resource-type IDs, class colors, and max-color eligibility.</li><li>`ns.L` — localized labels/tooltips.</li><li>`LibSettingsBuilder` row schema — the page spec returned here is consumed by the root options registration in `UI/Options.lua`.</li></ul> |

## 2. Actor diagram

```mermaid
sequenceDiagram
    autonumber
    participant Game as Game (WoW client)
    participant ACE as ACE (AceAddon / AceDB / CallbackHandler)
    participant ECM as ECM (addon root)
    participant Runtime as Runtime
    participant RB as ResourceBar
    participant Deps as Deps (BarMixin, ClassUtil,<br/>FrameUtil, LibEditMode, Constants)

    rect rgb(26,26,46)
    note over Game,Deps: Addon startup and first render
    Game->>ACE: ADDON_LOADED / module load
    ACE->>RB: OnInitialize()
    RB->>Deps: BarMixin.AddBarMixin(self, "ResourceBar")
    Game->>ACE: PLAYER_LOGIN
    ACE->>ECM: OnEnable()
    ECM->>Runtime: Runtime.Enable(addon)
    Runtime->>ACE: EnableModule("ResourceBar")
    ACE->>RB: OnEnable()
    RB->>RB: EnsureFrame()
    RB->>Runtime: RegisterFrame(self)
    RB->>Game: RegisterEvent(UNIT_AURA)
    RB->>Game: RegisterEvent(UNIT_POWER_UPDATE)
    Runtime->>RB: UpdateLayout("ModuleInit")
    RB->>Deps: FrameProto.ApplyFramePosition() / FrameUtil lazy setters
    RB->>RB: ThrottledRefresh("UpdateLayout")
    RB->>Deps: ClassUtil.GetPlayerResourceType()
    RB->>Deps: ClassUtil.GetCurrentMaxResourceValues()
    RB->>Deps: FrameUtil texture/color updates
    RB->>RB: GetTickSpec() -> EnsureTicks() -> LayoutResourceTicks()
    end

    rect rgb(26,46,30)
    note over Game,Deps: Shared runtime layout pulse reaches ResourceBar
    Game->>Runtime: layout event (mount/combat/zone/spec/target/edit-preview state)
    Runtime->>Runtime: updateFadeAndHiddenStates()
    Runtime->>RB: UpdateLayout(reason)
    RB->>Deps: FrameProto.ApplyFramePosition() / background / border
    RB->>RB: ThrottledRefresh(reason)
    RB->>Deps: GetStatusBarValues() / GetStatusBarColor() / GetTickSpec()
    RB->>Deps: EnsureTicks() / LayoutResourceTicks()
    end

    rect rgb(46,30,46)
    note over Game,Deps: Module data event — UNIT_POWER_UPDATE
    Game->>RB: UNIT_POWER_UPDATE(unit = "player", ...)
    RB->>RB: OnEventUpdate(event, unit)
    RB->>Runtime: RequestRefresh(self, "UNIT_POWER_UPDATE")
    Runtime->>RB: ThrottledRefresh("UNIT_POWER_UPDATE")
    RB->>Deps: ClassUtil.GetPlayerResourceType()
    RB->>Deps: ClassUtil.GetCurrentMaxResourceValues()<br/>(secret-bearing power path)
    RB->>RB: GetStatusBarColor() / GetTickSpec()
    end

    rect rgb(30,30,60)
    note over Game,Deps: Module data event — UNIT_AURA
    Game->>RB: UNIT_AURA(unit = "player", ...)
    RB->>RB: OnEventUpdate(event, unit)
    RB->>Runtime: RequestRefresh(self, "UNIT_AURA")
    Runtime->>RB: ThrottledRefresh("UNIT_AURA")
    RB->>Deps: ClassUtil.GetPlayerResourceType()
    RB->>Deps: ClassUtil.GetCurrentMaxResourceValues()<br/>(secret-bearing aura path)
    RB->>RB: GetStatusBarColor() / GetTickSpec()
    end

    rect rgb(46,40,26)
    note over Game,Deps: Profile change
    Game->>ACE: profile switched / copied / reset
    ACE->>ECM: OnProfileChangedHandler()
    ECM->>Runtime: Runtime.Enable(addon)
    ECM->>Runtime: ScheduleLayoutUpdate(0, "ProfileChanged")
    Runtime->>RB: UpdateLayout("ProfileChanged")
    RB->>Deps: Re-read live config from AceDB
    RB->>RB: Refresh with new width/colors/tick behavior
    end

    rect rgb(46,26,30)
    note over Game,Deps: Options change
    Game->>Deps: Settings row changed in ResourceBar options
    Deps->>Runtime: ScheduleLayoutUpdate(0, "OptionsChanged")
    Runtime->>RB: UpdateLayout("OptionsChanged")
    RB->>Deps: GetModuleConfig() / GetGlobalConfig()
    RB->>RB: Refresh with updated appearance/config
    end

    rect rgb(26,40,46)
    note over Game,Deps: Edit Mode enter / exit
    Game->>Deps: LibEditMode enter or exit callback
    Deps->>Runtime: ScheduleLayoutUpdate(0, "EditModeEnter" / "EditModeExit")
    Runtime->>RB: UpdateLayout(reason)
    RB->>Deps: FrameProto.ApplyFramePosition()
    RB->>RB: Refresh while force-visible
    end

    rect rgb(36,26,46)
    note over Game,Deps: Edit Mode drag / width slider
    Game->>Deps: drag frame or change width slider
    Deps->>Runtime: UpdateLayoutImmediately("EditModeDrag" / "EditModeWidth")
    Runtime->>RB: UpdateLayout(reason)
    RB->>Deps: ApplyFramePosition() with saved Edit Mode position
    RB->>RB: Refresh and recompute ticks against new width
    end
```

## 3. Component interaction diagram (UML)

```mermaid
flowchart LR
    subgraph IN[Inbound callers]
        ACE[ACE / ECM lifecycle<br/>OnInitialize, OnEnable, OnDisable]
        GAME[WoW events<br/>UNIT_POWER_UPDATE, UNIT_AURA]
        RT[Runtime<br/>UpdateLayout, RequestRefresh]
        UX[Options, profile, Edit Mode<br/>via Runtime scheduling]
    end

    subgraph CORE[ResourceBar module]
        RB[ResourceBar<br/>Modules/ResourceBar.lua]
    end

    subgraph DIRECT[Direct module dependencies]
        ADDON[ns.Addon<br/>Ace module owner]
        BM[BarMixin.AddBarMixin<br/>BarProto + FrameProto]
        CU[ClassUtil<br/>resource type and values]
        CONST[Constants<br/>resource IDs and gates]
        RTA[Runtime API<br/>RegisterFrame / RequestRefresh]
    end

    subgraph INHERITED[Inherited services used during layout/refresh]
        FP[FrameProto<br/>EnsureFrame, UpdateLayout,<br/>ApplyFramePosition, GetModuleConfig]
        BP[BarProto<br/>Refresh, EnsureTicks,<br/>LayoutResourceTicks]
        FU[FrameUtil<br/>anchors, alpha, texture,<br/>status-bar color]
        EM[EditMode / LibEditMode<br/>saved positions and width slider]
        DB[AceDB profile<br/>resourceBar + global]
    end

    ACE -->|constructs / enables / disables| RB
    GAME -->|dispatches player-only module events| RB
    RT -->|calls layout and values refresh paths| RB
    UX -->|schedules runtime pulses that reach| RT

    RB -->|created by| ADDON
    RB -->|mixes in| BM
    RB -->|queries active resource type and values| CU
    RB -->|reads resource constants and color gates| CONST
    RB -->|registers with / asks for refresh from| RTA

    RB -->|inherits geometry / visibility logic from| FP
    RB -->|inherits status-bar + tick logic from| BP
    FP -->|applies lazy frame mutations through| FU
    FP -->|reads live config from| DB
    FP -->|registers frame settings with| EM
    BP -->|uses setters and pixel snapping from| FU

    style ACE fill:#1a1a2e,stroke:#f7a855,color:#e0e0e0
    style GAME fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
    style RT fill:#16213e,stroke:#7a84f7,color:#e0e0e0
    style UX fill:#1a1a2e,stroke:#f43f5e,color:#e0e0e0
    style RB fill:#1a1a2e,stroke:#4cc9f0,color:#e0e0e0
    style ADDON fill:#1a1a2e,stroke:#7a84f7,color:#e0e0e0
    style BM fill:#1a1a2e,stroke:#7a84f7,color:#e0e0e0
    style CU fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
    style CONST fill:#1a1a2e,stroke:#f7a855,color:#e0e0e0
    style RTA fill:#1a1a2e,stroke:#f43f5e,color:#e0e0e0
    style FP fill:#1a1a2e,stroke:#4cc9f0,color:#e0e0e0
    style BP fill:#1a1a2e,stroke:#4cc9f0,color:#e0e0e0
    style FU fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
    style EM fill:#1a1a2e,stroke:#a855f7,color:#e0e0e0
    style DB fill:#1a1a2e,stroke:#f7a855,color:#e0e0e0
```

## 4. Data model class diagram

`Defaults.lua` seeds `resourceBar` with `enabled = true`, `showText = false`, `anchorMode = "chain"`, `width = 300`, empty `editModePositions`, a disabled border block, resource color tables, and max-color tables for the resource types gated in `Constants.lua`.

```mermaid
classDiagram
    class ResourceBarModule {
        +Name: string
        +InnerFrame: Frame
        +IsHidden: boolean
        -_configKey: string
        -_mixinApplied: boolean
        -_lastUpdate: number
        -_editModeRegisteredFrame: Frame
        +tickPool: Texture[]
        +ShouldShow() boolean
        +GetStatusBarValues() tuple
        +GetStatusBarColor() ECM_Color
        +GetTickSpec() ECM_ResourceTickSpec
        +OnEventUpdate(event, unit)
        +OnInitialize()
        +OnEnable()
        +OnDisable()
    }

    class FrameProto {
        +EnsureFrame()
        +UpdateLayout(why) boolean
        +ApplyFramePosition() table
        +GetModuleConfig() ECM_ResourceBarConfig
        +SetHidden(hide)
        +ThrottledRefresh(why) boolean
    }

    class BarProto {
        +Refresh(why, force) boolean
        +EnsureTicks(count, parentFrame, poolKey)
        +HideAllTicks(poolKey)
        +LayoutResourceTicks(maxResources, color, width, poolKey)
        +GetStatusBarValues()
        +GetStatusBarColor() ECM_Color
    }

    class ECM_Profile {
        +resourceBar: ECM_ResourceBarConfig
        +global: ECM_GlobalConfig
    }

    class ECM_BarConfigBase {
        +enabled: boolean
        +editModePositions: map
        +width: number
        +height: number?
        +texture: string?
        +overrideFont: boolean
        +font: string?
        +fontSize: number?
        +showText: boolean?
        +bgColor: ECM_Color?
        +anchorMode: string
    }

    class ECM_ResourceBarConfig {
        +colors: map
        +maxColors: map
        +maxColorsEnabled: map
        +border: ECM_BorderConfig
    }

    class ECM_BorderConfig {
        +enabled: boolean
        +thickness: number
        +color: ECM_Color
    }

    class ECM_Color {
        +r: number
        +g: number
        +b: number
        +a: number
    }

    class ECM_ResourceTickSpec {
        +maxResources: number
        +color: ECM_Color
        +width: number
    }

    class ECM_GlobalConfig {
        +barHeight: number
        +barBgColor: ECM_Color
        +texture: string
        +updateFrequency: number
        +moduleGrowDirection: string
        +detachedBarWidth: number
    }

    class ECM_ResourceType {
        <<enumeration>>
        ComboPoints
        Chi
        HolyPower
        Essence
        SoulShards
        ArcaneCharges
        souls
        devourerNormal
        devourerMeta
        icicles
        maelstromWeapon
    }

    class ClassUtil {
        +GetPlayerResourceType() ECM_ResourceType
        +GetCurrentMaxResourceValues(resourceType) tuple
    }

    ResourceBarModule --|> BarProto
    BarProto --|> FrameProto
    ECM_ResourceBarConfig --|> ECM_BarConfigBase
    ECM_Profile *-- ECM_ResourceBarConfig : resourceBar
    ECM_Profile *-- ECM_GlobalConfig : global
    ECM_ResourceBarConfig *-- ECM_BorderConfig : border
    ECM_BorderConfig *-- ECM_Color : color
    ECM_ResourceTickSpec *-- ECM_Color : color
    ResourceBarModule ..> ECM_ResourceTickSpec : returns
    ResourceBarModule ..> ECM_ResourceBarConfig : GetModuleConfig()
    ResourceBarModule ..> ECM_GlobalConfig : GetGlobalConfig()
    ResourceBarModule ..> ECM_ResourceType : active type
    ResourceBarModule ..> ClassUtil : queries type/max/current

    style ResourceBarModule fill:#1a1a2e,stroke:#4cc9f0,color:#e0e0e0
    style FrameProto fill:#1a1a2e,stroke:#7a84f7,color:#e0e0e0
    style BarProto fill:#1a1a2e,stroke:#7a84f7,color:#e0e0e0
    style ECM_Profile fill:#1a1a2e,stroke:#f7a855,color:#e0e0e0
    style ECM_BarConfigBase fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
    style ECM_ResourceBarConfig fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
    style ECM_BorderConfig fill:#1a1a2e,stroke:#a855f7,color:#e0e0e0
    style ECM_Color fill:#1a1a2e,stroke:#a855f7,color:#e0e0e0
    style ECM_ResourceTickSpec fill:#1a1a2e,stroke:#f43f5e,color:#e0e0e0
    style ECM_GlobalConfig fill:#1a1a2e,stroke:#f7a855,color:#e0e0e0
    style ECM_ResourceType fill:#1a1a2e,stroke:#22c55e,color:#e0e0e0
    style ClassUtil fill:#1a1a2e,stroke:#4cc9f0,color:#e0e0e0
```
