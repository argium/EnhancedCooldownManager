# Enhanced Cooldown Manager

WoW addon: customizable resource bars anchored to Blizzard's Cooldown Manager viewers.

## Guidelines

- Implement EXACTLY and ONLY what is requested
- Don't reach into other modules' internals
- Use `assert()`/`error()` for invariants; `pcall` for Blizzard/third-party frames
- No `type(x) == "function"` guards except for `issecretvalue`, `canaccessvalue`
- No upvalue caching (e.g., `local math_floor = math.floor`)
- Config: `EnhancedCooldownManager.db.profile` with module subsections

## Architecture

Blizzard frames: `EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffIconCooldownViewer`, `BuffBarCooldownViewer`

Bar stack: `EssentialCooldownViewer` → `PowerBar` → `ResourceBar` → `RuneBar` → `BuffBarCooldownViewer`

**Module interface**: `:GetFrame()`, `:GetFrameIfShown()`, `:SetExternallyHidden(bool)`, `:UpdateLayout()`, `:Refresh()`, `:Enable()`/`:Disable()`

## Mixins (`Modules/Mixins/`)

Bar modules use object-based mixins (methods attached directly to bar frames):

### BarFrame
Frame creation, layout, appearance, text overlay, and module setup. Bar-specific mixin.

**Module Setup (entry point):**
- `BarFrame.Setup(module, config)` - Orchestrates Lifecycle + bar config, injects UpdateLayout

**Constants:** `DEFAULT_POWER_BAR_HEIGHT`, `DEFAULT_RESOURCE_BAR_HEIGHT`, `DEFAULT_BG_COLOR`

**Helpers:** `GetBarHeight()`, `GetTopGapOffset()`, `GetBgColor()`, `GetTexture()`, `ApplyFont()`, `ResolveAnchor()`

**Anchoring:** `GetViewerAnchor()`, `GetPreferredAnchor(addon, excludeModule)`, `ResolveAnchor(addon, cfg, moduleName)`

**Bar methods (attached during Create):**
- `bar:SetLayout(anchor, offsetX, offsetY, height, width)` - Apply layout (cached)
- `bar:SetAppearance(cfg, profile)` - Apply appearance (bg color, texture)
- `bar:SetValue(min, max, current, r, g, b)` - Update StatusBar value and color
- `bar:ApplyConfig(module)` - Complete layout/appearance from profile (called by UpdateLayout)

**Text methods (attached via AddTextOverlay):**
- `bar:SetText(text)`
- `bar:SetTextVisible(shown)`

### ModuleLifecycle
Generic event handling mixin. Enable/Disable, event registration, throttled refresh.

**Injected methods:** `OnEnable`, `OnDisable`, `SetExternallyHidden`, `GetFrameIfShown`

**Config:** Name, layoutEvents, refreshEvents, onDisable callback

**Note:** Does NOT inject UpdateLayout (that's BarFrame's job). Modules must define their own UpdateLayout or use BarFrame.Setup.

### TickRenderer
Tick pooling and positioning. Attaches methods to bars via `TickRenderer.AttachTo(bar)`.

**Bar methods:** `bar:EnsureTicks()`, `bar:HideAllTicks()`, `bar:LayoutResourceTicks()`, `bar:LayoutValueTicks()`

## Creating a New Bar Module

```lua
local MyBar = EnhancedCooldownManager:NewModule("MyBar", "AceEvent-3.0")

-- Domain logic
local function ShouldShow() return profile.myBar.enabled end
local function GetValues(profile) return max, current, kind end

-- Frame creation
function MyBar:GetFrame()
    if self._frame then return self._frame end
    self._frame = BarFrame.Create(ADDON_NAME .. "MyBar", UIParent, BarFrame.DEFAULT_RESOURCE_BAR_HEIGHT)
    TickRenderer.AttachTo(self._frame)  -- optional
    BarFrame.AddTextOverlay(self._frame, profile)  -- optional
    return self._frame
end

-- Value updates
function MyBar:Refresh()
    local bar = self._frame
    local max, current, kind = GetValues(profile)
    bar:SetValue(0, max, current, cfg.colors[kind][1], cfg.colors[kind][2], cfg.colors[kind][3])
end

-- Module setup (UpdateLayout is injected by BarFrame.Setup)
BarFrame.Setup(MyBar, {
    name = "MyBar",
    configKey = "myBar",
    shouldShow = ShouldShow,
    layoutEvents = { "PLAYER_ENTERING_WORLD" },
    refreshEvents = { { event = "UNIT_POWER_UPDATE", handler = "OnRefresh" } },
})

-- Optional: module-specific layout completion hook
function MyBar:OnLayoutComplete(bar, cfg, profile)
    -- Module-specific setup after layout (return false to abort)
    local maxResources = GetValues(profile)
    if not maxResources or maxResources <= 0 then
        bar:Hide()
        return false
    end
    bar.StatusBar:SetMinMaxValues(0, maxResources)
    bar:EnsureTicks(maxResources - 1, bar.TicksFrame, "ticks")
    bar:LayoutResourceTicks(maxResources, { 0, 0, 0, 1 }, 1, "ticks")
    return true
end
```

**Profile config** (in `EnhancedCooldownManager.lua` defaults):
```lua
myBar = {
    enabled = true,
    height = nil,  -- defaults to global.barHeight
    texture = nil,  -- defaults to global.texture
    anchorMode = "chain",  -- "viewer" or "chain"
    offsetX = 0,  -- horizontal offset from anchor
    -- module-specific config...
},
```

## Utilities

`Util.Log()` for debug logging, `Util.PixelSnap()` for pixel-perfect positioning. Layout/appearance helpers have moved to BarFrame.

## Secret Values

In combat/instances, many Blizzard API returns are restricted. Cannot compare, convert type, or concatenate.

- `issecretvalue(v)` / `canaccessvalue(v)` to check
- `SafeGetDebugValue()` for debug output
- Avoid `C_UnitAuras` APIs using spellId; use `auraInstanceId` instead
