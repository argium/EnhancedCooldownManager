# Output verbosity
- Default: 3–6 sentences or ≤5 bullets for typical answers.
- For simple “yes/no + short explanation” questions: ≤2 sentences.
- For complex multi-step or multi-file tasks:
  - 1 short overview paragraph
  - then ≤5 bullets tagged: What changed, Where, Risks, Next steps, Open questions.
- Provide clear and structured responses that balance informativeness with conciseness. Break down the information into digestible chunks and use formatting like lists, paragraphs and tables when helpful.
- Avoid long narrative paragraphs; prefer compact bullets and short sections.
- Do not rephrase the user’s request unless it changes semantics.


# Context

EnhancedCooldownManager (ECM) is a WoW addon that adds customizable resource bars anchored to Blizzard's Cooldown Manager viewers.

## File Structure
- `EnhancedCooldownManager.lua` – Ace3 addon bootstrap, defaults, config type definitions, slash commands
- `Utilities.lua` – Shared helpers: `ns.Util.*` (PixelSnap, GetBgColor, GetBarHeight, GetTopGapOffset, GetTexture, GetFontPath, ApplyBarAppearance, ApplyBarLayout, ApplyFont, GetViewerAnchor, GetPreferredAnchor)
- `PowerBars.lua` – AceModule for primary resource bar (mana/rage/energy/runic power/etc.)
- `SegmentBar.lua` – AceModule for fragmented resources (DK runes, DH souls, Fury Warrior Whirlwind stacks)
- `BuffBars.lua` – AceModule that styles Blizzard's BuffBarCooldownViewer children
- `ViewerHook.lua` – Central event handler for mount/spec changes; calls `SetExternallyHidden(bool)` on modules and triggers layout updates

## Bar Modules

### PowerBars
Displays the player's primary resource (mana, rage, energy, focus, runic power, etc.) as a horizontal status bar with optional text overlay that are displayed as a whole bar.

- **What it shows:** Current/max power value; optionally mana as percentage. Tick marks for discrete resources (combo points, holy power, chi, soul shards, arcane charges, essence).
- **Visibility:** Hidden for DPS specs using mana, hidden for shapeshifted druids (cat/bear forms use different resources).
- **Frame structure:** `ECM_PowerBarFrame` with `.Background` (Texture), `.StatusBar` (StatusBar), `.TextFrame`/`.TextValue` (FontString), `.ticks[]` (Texture array).
- **Events:** `UNIT_POWER_UPDATE` for value updates.

### SegmentBar
Displays fragmented/segmented resources, shown as multiple sub-bars with tick dividers.

- **What it shows:** Death Knight runes (6 segments, fractional recharge progress with sorted display), Demon Hunter souls (stack-based aura count via spell ID lookup), or Fury Warrior Whirlwind stacks (secret-safe aura lookup).
- **Visibility:** Only shown for DK, DH, and Fury Warrior (specID 72) when enabled.
- **Frame structure:** `ECM_SegmentBarFrame` with `.Background`, `.StatusBar` (for non-fragmented like souls/whirlwind), `.TicksFrame`, `.ticks[]`, `.FragmentedBars[]` (individual StatusBars per rune).
- **Events:** `RUNE_POWER_UPDATE` + `OnUpdate` for DK runes; `UNIT_AURA` for DH souls and Warrior Whirlwind.

### BuffBars
Styles Blizzard's `BuffBarCooldownViewer` children with custom textures, colors, fonts, and layout. Does NOT create its own frames—it reskins existing Blizzard buff bar frames.

- **What it shows:** Active buff/cooldown bars from Blizzard's Cooldown Manager system.
- **Visibility:** Controlled by Blizzard; ECM only styles and repositions.
- **Frame structure:** Hooks into `BuffBarCooldownViewer:GetChildren()`. Each child has `.Bar` (StatusBar), `.Icon`/`.IconFrame`/`.IconButton`, `.Bar.Name`, `.Bar.Duration`.
- **Events:** `UNIT_AURA` for rescan triggers; hooks `OnShow`/`OnSizeChanged` on the viewer; hooks `EditModeManagerFrame` for edit mode transitions.
- **Dynamic styling:** Per-spell overrides via `profile.dynamicBars` array with `auraSpellIds` mapping.

### Layout Relationship
Bars stack vertically below `EssentialCooldownViewer`:
```
EssentialCooldownViewer (Blizzard icons)
    ↓ PowerBar (if visible)
    ↓ SegmentBar (if visible)
    ↓ BuffBarCooldownViewer (Blizzard, restyled by BuffBars)
```
Each bar anchors to the bottom of the previous visible bar using `Util.GetPreferredAnchor()`.

### Common Module Interface
All bar modules expose:
| Method | Description |
|--------|-------------|
| `:GetFrame()` | Lazy-creates and returns the module's frame |
| `:GetFrameIfShown()` | Returns frame only if currently visible (for anchor chaining) |
| `:SetExternallyHidden(bool)` | Hides frame externally (e.g., mounted); does NOT unregister events |
| `:UpdateLayout()` | Positions/sizes/styles the frame, then calls `:Refresh()` |
| `:Refresh()` | Updates values only (colors, text, progress) |
| `:Enable()` / `:Disable()` | Registers/unregisters power/aura events |
| `:OnEnable()` / `:OnDisable()` | AceModule lifecycle hooks |

## Anchor Chain
Bars anchor in order: `EssentialCooldownViewer → PowerBar → SegmentBar → BuffBarCooldownViewer`
Use `Util.GetPreferredAnchor(addon, excludeModule)` to find the bottom-most visible ECM bar.

## Configuration
- All settings live in `EnhancedCooldownManager.db.profile`
- Module-specific configs: `profile.powerBar`, `profile.segmentBar`, `profile.dynamicBars`
- Global defaults: `profile.global.barHeight`, `.texture`, `.font`, `.fontSize`, `.barBgColor`
- Color overrides: `profile.powerTypeColors.colors[PowerType]`, `.special.deathKnight.runes[specID]`

## Key APIs
- `Util.GetBarHeight(cfg, profile, fallback)` – resolves height with pixel-snap
- `Util.ApplyBarAppearance(bar, cfg, profile)` – sets bg color + statusbar texture
- `Util.ApplyBarLayout(bar, anchor, height, width, offsetX, offsetY, matchAnchorWidth)` – positions bar
- `Util.ApplyFont(fontString, profile)` – applies global font settings
- Blizzard viewer frames: `EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffIconCooldownViewer`, `BuffBarCooldownViewer`

# Design and scope constraints

- Implement EXACTLY and ONLY what the user requests.
- Explore any existing design systems and understand it deeply.
- No extra features, no added components, no UX embellishments.
- Style aligned to the design system at hand.
- Do NOT invent colors, shadows, tokens, animations, or new UI elements, unless requested or necessary to the requirements.
- If any instruction is ambiguous, choose the simplest valid interpretation.

# Engineering quality guidelines

- You are to write code as an experienced software engineer adhering to best practices.
- Write clean, maintainable, and efficient code.
- Take care of performance when modifying hot paths.
- Ensure clear separation of concerns and modularity. Modules should have as small of an interface that is necessary for their function.
- Do not reach into another module’s internals (e.g., directly manipulating another module’s private frames/state).
- Prefer `assert(...)`/`error(...)` with clear messages for internal invariants (missing module, unexpected state).
- Write code that is easy to read and understand. Use meaningful names for variables, functions,
- Do not add or retain `type(x) == "function"` / `type(x) ~= "function"` guards except when working with functions that are part of a future update (see below).
- Ignore migration of settings unless explicitly requested.
- For interactions with Blizzard/third-party frames where a method may not exist, prefer `pcall` around the call over `type(...)` checks.
- Remove unused code
- Minimise code duplication by creating shared helper functions or restructuring modules
- It is OK to query API documentation: https://www.townlong-yak.com/framexml/beta/Blizzard_APIDocumentation

## WoW globals: do not create "global bindings"

- Do **NOT** add file-scope aliases like:
  - `-- Global bindings (helps linting and avoids accidental global lookups)`
  - `local ReloadUI = ...`, `local StaticPopupDialogs = ...`, `local YES = ...`, etc.
- Prefer using WoW globals directly at the call site (e.g., `ReloadUI()`, `StaticPopupDialogs[...]`, `C_AddOns.DisableAddOn(...)`).
- If a global may be missing in some clients/versions, use a *narrow, inline* lookup (`rawget(_G, "Thing")`) at the point of use rather than creating a shared file-level binding.

## Functions that are part of a future update

- issecretvalue(value): returns true if the supplied value is secret.
- canaccesssecrets(): returns false if the immediate calling function cannot access secret values - ie. because execution is tainted.
- canaccessvalue(value): returns true if the given value is either not secret, or if the calling function is permitted to access secret values.
- issecrettable(table): returns true if a table has been marked as secret.
- canaccesstable(table): returns true if the given table is either not secret, or if access to secrets is permitted for the calling function.

## Secret value restrictions

**CRITICAL:** Many values returned from Blizzard APIs (spell IDs, aura data, UI text from buff bars, etc.) may be "secret values". Secret values have severe restrictions:
- You CANNOT compare them (`==`, `~=`, `<`, `>`, etc.) - this will error
- You CANNOT use them in string concatenation
- You CANNOT use them with `tonumber()`, `tostring()`, or other Lua functions
- You CANNOT use `pcall` to work around these restrictions - comparisons inside pcall still error
- You CAN ONLY pass them by reference to other functions that accept them (e.g., Blizzard APIs, or SafeGetDebugValue for debug output)

When working with potentially secret values:
1. Never compare the value to anything (not even `nil` or empty string checks)
2. Pass directly to functions that handle them (e.g., `DebugPrint` which uses `SafeGetDebugValue`)
3. Use `issecretvalue(v)` to check if a value is secret before attempting operations
4. Use `canaccessvalue(v)` to check if you can safely use the value

## Functions that cannot be used

Auras with spell IDs. Use APIs that rely on auraInstanceId instead (because of secret restrictions).
- C_UnitAuras.GetPlayerAuraBySpellID(spellID)
- C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)

# Serena MCP Tools (Lua Plugin)

Serena provides semantic code navigation and editing via a Lua language server. Prefer these over raw text operations when working with symbols.

## Code Navigation
| Tool | Use Case |
|------|----------|
| `get_symbols_overview` | First step - lists all functions, methods, variables in a file |
| `find_symbol` | Search by name pattern (e.g., `PowerBars:Refresh`), with optional source body |
| `find_referencing_symbols` | Find all callers/usages of a symbol |
| `search_for_pattern` | Regex search with context lines, flexible file filtering |

## Code Editing
| Tool | Use Case |
|------|----------|
| `replace_symbol_body` | Replace entire function/method definition |
| `insert_before_symbol` / `insert_after_symbol` | Add new code adjacent to existing symbols |
| `rename_symbol` | Rename across entire codebase |
| `replace_content` | Regex-based find/replace for partial/line-level edits |

## Lua Symbol Types
Variables, Objects, Functions, Methods, Strings, Arrays - with nesting depth for class methods (e.g., `PowerBars:Refresh` nested under `PowerBars`).

## Navigation Examples
```
# Get overview of a module
get_symbols_overview("PowerBars.lua", depth=1)

# Find a specific method with source
find_symbol("PowerBars:UpdateLayout", include_body=true)

# Find all callers of UpdateLayout
find_referencing_symbols("PowerBars:UpdateLayout", "PowerBars.lua")

# Regex search for all :UpdateLayout() calls
search_for_pattern(":UpdateLayout\\(\\)", context_lines_before=1, context_lines_after=1)
```

## Best Practices
- Use `get_symbols_overview` before reading full files
- Use `find_symbol` with `include_body=true` only when you need the source
- Use `find_referencing_symbols` before renaming or changing signatures
- Prefer `replace_symbol_body` over text edits for whole functions
- Use `replace_content` with regex wildcards (e.g., `beginning.*?end`) for efficient partial edits
