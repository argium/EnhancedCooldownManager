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

Bar stack: `EssentialCooldownViewer` → `PowerBar` → `SegmentBar` → `BuffBarCooldownViewer`

Use `Util.GetPreferredAnchor(addon, excludeModule)` for anchor chaining.

**Module interface**: `:GetFrame()`, `:GetFrameIfShown()`, `:SetExternallyHidden(bool)`, `:UpdateLayout()`, `:Refresh()`, `:Enable()`/`:Disable()`

## Secret Values

In combat/instances, many Blizzard API returns are restricted. Cannot compare, convert type, or concatenate.

- `issecretvalue(v)` / `canaccessvalue(v)` to check
- `SafeGetDebugValue()` for debug output
- Avoid `C_UnitAuras` APIs using spellId; use `auraInstanceId` instead

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
