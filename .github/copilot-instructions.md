Enhanced Cooldown Manager (ECM) is a World of Warcraft addon that displays customizable resource bars anchored to Blizzard's Cooldown Manager viewer UI frames. It provides visual feedback for player power resources (eg. mana) and special resources (eg. combo points).

## Engineering Guidelines

- Implement EXACTLY and ONLY what is requested
- Do not reach into another module's internals
- Prefer `assert()`/`error()` with clear messages for internal invariants
- For Blizzard/third-party frames where methods may not exist, prefer `pcall` over `type(...)` checks
- Do not add `type(x) == "function"` guards except for future-update functions (`issecretvalue`, `canaccessvalue`, etc.)
- Remove unused code; minimize duplication via shared helpers
- **Do NOT use upvalue caching** (e.g., `local math_floor = math.floor`) - use standard Lua/WoW globals directly
- All settings in `EnhancedCooldownManager.db.profile`. Modules have their own settings section and may reference global or debat default options.
- Use `Util.GetPreferredAnchor(addon, excludeModule)` to find the bottom-most visible ECM bar.

The build-in cooldown viewer has the following well-known frames: "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer"

### Common Module Interface

- Use consistent semantics for common methods when creating new modules:

| Method | Description |
|--------|-------------|
| `:GetFrame()` | Lazy-creates and returns the module's frame |
| `:GetFrameIfShown()` | Returns frame only if currently visible (for anchor chaining) |
| `:SetExternallyHidden(bool)` | Hides frame externally (e.g., mounted); does NOT unregister events |
| `:UpdateLayout()` | Positions/sizes/styles the frame, then calls `:Refresh()` |
| `:Refresh()` | Updates values only (colors, text, progress) |
| `:Enable()` / `:Disable()` | Registers/unregisters power/aura events |

### Critical: Secret Value Handling

- Many Blizzard APIs are severely restricted in how they and their return values can be used. This regime is in effect typically when in combat or in instances, and affect: spell IDs, spell names, aura data, UI text.
- Secret values CAN be passed by "reference" but CANNOT be: compared, converted to a different type, concatenated in a string, bypassed with `pcall`.
- Some Blizzard functions can accept secret parameters.
-  Use `issecretvalue(v)` to check if a value is secret
- Use `canaccessvalue(v)` to check if you can safely use the value
- Pass to `SafeGetDebugValue()` for debug output

**Forbidden APIs** (due to secret restrictions):
- C_UnitAuras APIs that use spellId; use `auraInstanceId` functions instead.
- Spell IDs from `GetSpellID()`
- Spell names from `fontString:GetText()` on buff/aura bars

## Serena MCP Tools (Lua Plugin)

Serena provides semantic code navigation and editing for this Lua codebase. Prefer these tools over raw text search/replace when working with symbols.

## Code Navigation
| Tool | Use Case |
|------|----------|
| `get_symbols_overview` | First step to understand a file - lists all functions, methods, variables |
| `find_symbol` | Search by name pattern (e.g., `PowerBars:Refresh`), optionally include source body |
| `find_referencing_symbols` | Find all callers/usages of a symbol |
| `search_for_pattern` | Regex search with context lines, flexible file filtering |

## Code Editing
| Tool | Use Case |
|------|----------|
| `replace_symbol_body` | Replace entire function/method definition |
| `insert_before_symbol` / `insert_after_symbol` | Add new code adjacent to existing symbols |
| `rename_symbol` | Rename across entire codebase |
| `replace_content` | Regex-based find/replace within files (for partial edits) |

## Lua Symbol Types Recognized
Variables, Objects, Functions, Methods, Strings, Arrays - with nesting depth support for class methods.

## Best Practices
- Use `get_symbols_overview` before reading full files
- Use `find_symbol` with `include_body=true` only when you need the source
- Use `find_referencing_symbols` before renaming/changing signatures
- Prefer `replace_symbol_body` over text-based edits for whole functions
- Use `replace_content` with regex for surgical line-level changes
