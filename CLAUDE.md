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

Bar stack: `EssentialCooldownViewer` → `PowerBar` → `SegmentBar` → `RuneBar` → `BuffBarCooldownViewer`

**Module interface**: `:GetFrame()`, `:GetFrameIfShown()`, `:SetExternallyHidden(bool)`, `:UpdateLayout()`, `:Refresh()`, `:Enable()`/`:Disable()`

## Mixins (`Modules/Mixins/`)

Bar modules use object-based mixins (methods attached directly to bar frames):

### BarFrame
Frame creation, layout, appearance, text overlay. Constants and helpers for styling.

**Constants:** `DEFAULT_POWER_BAR_HEIGHT`, `DEFAULT_SEGMENT_BAR_HEIGHT`, `DEFAULT_BG_COLOR`

**Helpers:** `GetBarHeight()`, `GetTopGapOffset()`, `GetBgColor()`, `GetTexture()`, `ApplyFont()`

**Anchoring:** `GetViewerAnchor()`, `GetPreferredAnchor(addon, excludeModule)`

**Bar methods (attached during Create):**
- `bar:ApplyLayout(anchor, offsetY, height, width, matchAnchorWidth)`
- `bar:ApplyLayoutAndAppearance(anchor, offsetY, cfg, profile, defaultHeight)`
- `bar:ApplyAppearance(cfg, profile)`
- `bar:SetValue(min, max, current, r, g, b)`

**Text methods (attached via AddTextOverlay):**
- `bar:SetText(text)`
- `bar:SetTextVisible(shown)`

### ModuleLifecycle
Enable/Disable, event registration, throttled refresh. Injects methods onto modules.

**Injected methods:** `OnEnable`, `OnDisable`, `SetExternallyHidden`, `GetFrameIfShown`

**Auto-generated UpdateLayout:** When `configKey` is provided, injects a default `UpdateLayout` that:
1. Checks preconditions (profile, enabled, shouldShow)
2. Calculates anchor based on `anchorMode` ("viewer" or "chain")
3. Applies layout and appearance
4. Calls `onLayoutSetup` hook for module-specific setup
5. Shows bar and calls Refresh

### TickRenderer
Tick pooling and positioning. Attaches methods to bars via `TickRenderer.AttachTo(bar)`.

**Bar methods:** `bar:EnsureTicks()`, `bar:HideAllTicks()`, `bar:LayoutSegmentTicks()`, `bar:LayoutValueTicks()`

## Creating a New Bar Module

```lua
local MyBar = EnhancedCooldownManager:NewModule("MyBar", "AceEvent-3.0")

-- Domain logic
local function ShouldShow() return profile.myBar.enabled end
local function GetValues(profile) return max, current, kind end

-- Frame creation
function MyBar:GetFrame()
    if self._frame then return self._frame end
    self._frame = BarFrame.Create(ADDON_NAME .. "MyBar", UIParent, BarFrame.DEFAULT_SEGMENT_BAR_HEIGHT)
    TickRenderer.AttachTo(self._frame)  -- optional
    BarFrame.AddTextOverlay(self._frame, profile)  -- optional
    return self._frame
end

-- Value updates
function MyBar:Refresh()
    local bar = self._frame
    local max, current, kind = GetValues(profile)
    bar.StatusBar:SetValue(current)
    bar.StatusBar:SetStatusBarColor(cfg.colors[kind][1], cfg.colors[kind][2], cfg.colors[kind][3])
end

-- Configuration (UpdateLayout is auto-generated)
Lifecycle.Setup(MyBar, {
    name = "MyBar",
    configKey = "myBar",
    shouldShow = ShouldShow,
    defaultHeight = BarFrame.DEFAULT_SEGMENT_BAR_HEIGHT,
    anchorMode = "chain",  -- or "viewer"
    layoutEvents = { "PLAYER_ENTERING_WORLD" },
    refreshEvents = { { event = "UNIT_POWER_UPDATE", handler = "OnRefresh" } },
    onLayoutSetup = function(self, bar, cfg, profile)
        -- Module-specific setup after layout (return false to abort)
    end,
})
```

## Utilities

`Util.Log()` for debug logging, `Util.PixelSnap()` for pixel-perfect positioning. Layout/appearance helpers have moved to BarFrame.

## Secret Values

In combat/instances, many Blizzard API returns are restricted. Cannot compare, convert type, or concatenate.

- `issecretvalue(v)` / `canaccessvalue(v)` to check
- `SafeGetDebugValue()` for debug output
- Avoid `C_UnitAuras` APIs using spellId; use `auraInstanceId` instead
