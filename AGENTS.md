- Be concise with your responses.
- Be professional but honest.
- Use mermaid diagrams and tables to explain complex concepts and architecture.
- Do not commit changes after making them. The user prefers to commit manually.

---

# Validation

```sh
# Run addon tests
busted Tests

# Run library tests (each library owns its tests in Libs/<Name>/Tests/)
busted --run libsettingsbuilder
busted --run libconsole
busted --run libevent
busted --run liblsmsettingswidgets

# Lint
luacheck . -q
```

- Changes to addon code (`Modules/`, `Helpers/`, `UI/`, `ECM*.lua`) MUST pass `busted Tests` and `luacheck . -q`.
- Changes to a library MUST also pass its dedicated test suite (e.g. `busted --run libconsole`).
- Run the relevant suite(s) **before** and **after** every change to confirm you haven't introduced regressions.

---

# Coding

<CopyrightHeader>
-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
</CopyrightHeader>

## Mandatory Rules

- **ALL constants** must be stored in `ECM_Constants.lua`. No inline magic numbers or strings.
- **DO NOT nil-check or wrap built-in functions** such as `issecretvalue`, `issecrettable`, `canaccesstable`.
- **New features or regression fixes** in `/Modules`, `/Helpers`, `/UI`, and `ECM.lua` MUST include corresponding test cases.
- **All Lua files** must include the standard copyright header (see above).
- Anything more than a small, targeted fix MUST perform a code review as the final step (see Code Review section below).

## Lua Environment

- WoW runs **Lua 5.1**. Do not use `goto`/labels (Lua 5.2+), `//` integer division (Lua 5.3+), or other post-5.1 features.
- `busted` tests run on **Lua 5.3+**. If a shim is needed only for the test runner (e.g. `wipe()`), add a comment explaining why.
- Do not add Lua version compatibility shims for built-ins that already exist in WoW's runtime (e.g. `unpack`, `table.getn`).

## Config Access

Modules that use ModuleMixin must use live config accessors. **Never** access `mod.db` or `mod.db.profile` directly. **Never** create an intermediate table for profile/config.

```lua
-- Module code
local config = self:GetModuleConfig()    -- module-specific settings
local global = self:GetGlobalConfig()    -- shared global block
```

Non-module code (Runtime, ECM.lua helpers) must use the shared standalone accessor:

```lua
local global = ECM.GetGlobalConfig()
```

**Never** inline `ns.Addon.db.profile.global` — always go through the accessor.

When a function reads the same config value multiple times, capture it in a local at the top of the scope. Do not re-traverse the accessor chain for the same field twice.

## Event Registration

All event callbacks must be **function references**, not method name strings. LibEvent does not support string-based callbacks.

```lua
-- Correct
self:RegisterEvent("UNIT_POWER_UPDATE", function(...) self:OnUnitPowerUpdate(...) end)

-- Wrong — will error
self:RegisterEvent("UNIT_POWER_UPDATE", "OnUnitPowerUpdate")
```

## Performance

- **NEVER** listen to the `OnUpdate` event. This includes perpetual `C_Timer.NewTicker` at frame-rate intervals. Prefer event-driven updates with a single deferred timer for animation tails.
- **Table reuse**: On hot paths (tickers, layout loops), pre-allocate tables and reuse them via `wipe()` instead of creating new tables each call.
- **Timer supersede**: When scheduling deferred work, cancel any pending timer before creating a new one. Lower-priority timers must not block higher-priority updates.
- **Guard debug logging**: When debug logging or string serialization is called on a hot path, guard with `if ECM.IsDebugEnabled() then` to avoid string concatenation overhead in production.
- **Zero-allocation dispatch**: Avoid snapshot-copying callback lists. Use index-based iteration with mid-loop removal handling.

## State & Scope

- Mutable state (flags, caches) must be scoped to the owning module instance (`self._field`), not file-level locals. File-level locals are only for truly global singletons or constants.
- Do not use forward declarations.
- When a file references a shared module (e.g. `ECM.FrameUtil`) more than once, alias it as a file-level local at the top. Do not repeat the full path at every call site.

```lua
local FrameUtil = ECM.FrameUtil   -- alias once at top
local EditMode = ECM.EditMode
```

## Libraries (`Libs/`)

Each private library is self-contained under `Libs/<Name>/` with its own `Tests/` and `README.md`. They will eventually be published as standalone packages.

- **API changes are allowed** (they're private now), but design for future stability — breaking changes to the public surface should be intentional and documented.
- Libraries must not depend on ECM internals (`ECM.Constants`, `ECM.FrameUtil`, etc.). They may depend on LibStub, LibSharedMedia, and WoW globals only.
- Library test specs live in `Libs/<Name>/Tests/` (not the addon's `Tests/` folder).
- Shared confirm dialogs use `ECM.OptionUtil.MakeConfirmDialog(text)` which returns a `StaticPopupDialogs` template. The pattern uses `data.onAccept` for per-button behavior via a single shared popup.

## Migrations

Migration functions in `Helpers/Migration.lua` are **frozen snapshots**. They must capture the data model as it existed at the time of the migration version. Do not reference live production code (e.g. `KeyType.lua`) from a migration — inline or duplicate the logic so future refactors cannot silently break old migrations.

---

# Architecture Invariants

These rules prevent recurring anti-patterns discovered during code review. Violations should be caught and fixed proactively.

## Single Source of Truth

- Each piece of shared state or derived value must have exactly one canonical accessor or derivation point. All other call sites must delegate to it.
- Do not create parallel accessor functions that reach the same underlying data through different paths. If a non-module caller needs access, expose a shared standalone function and alias it locally — don't reimplement the lookup.

## No Duplicate Utility Functions

- Pure-logic helpers (anchor geometry, color math, table operations, normalization, assertion helpers, builders) MUST live in one canonical shared location. File-local copies are prohibited unless the helper is truly single-use.
- Before writing a new local helper, search the codebase for an existing canonical implementation. If one exists, use it. If it's close but not quite right, extend the shared version — don't fork a copy.
- Do not copy-paste logic between production files, between test files, or across production/test boundaries.
- Do not create trivial passthrough wrappers that just forward arguments to another function. Callers should invoke the canonical function directly.
- Ownership of shared helper domains must remain explicit. When one module already owns a domain (e.g. anchor geometry, color math), extend that owner rather than creating a second implementation elsewhere.

## Test Integrity

- Test `before_each` / `LoadChunk` calls MUST mirror TOC load order. If file A depends on `ECM.B`, load file B first.
- Test stubs must replace the canonical function, not a wrapper or alias. When a passthrough is removed, its test stubs must move to the canonical location.
- Regression tests must exercise the live implementation wherever practical. Do not create mirrored helper logic in specs just to restate what production code already computes.
- If a test needs shared setup, expectation logic, or assertions, prefer an existing canonical helper in `Tests/TestHelpers.lua`; otherwise create one shared helper instead of copy-pasting across files.
- Test files mirror source folders: `Helpers/Util.lua` → `Tests/Helpers/Util_spec.lua`. Library tests live in `Libs/<Name>/Tests/`.
- `StaticPopup_Show` stubs must forward all 4 arguments `(name, text1, text2, data)` and pass `data` as the 2nd argument to `OnAccept(self, data)` to match WoW's real calling convention.

## Derive Once, Read Everywhere

- Transforms or derived keys (e.g. name casing conventions) MUST be computed in exactly one place and stored for later use. Other code reads the stored result — never re-derives it.
- Authoritative ordered lists (module order, chain order) should live in Constants.

## No Dead Code

- Do not leave unused fields, stale type annotations, or cleanup of non-existent state in teardown/disable methods.
- If a function parameter or fallback branch can never execute, remove it.
- `luacheck` does not catch unused locale entries. When UI labels or tooltips are removed, grep the corresponding `L["..."]` keys and delete any locale strings that became unused.

## Periodic Work Must Degrade Gracefully

- Tickers or polling loops that perform setup tasks (hooking frames, discovering late-created objects) must track completion and skip the setup calls once all targets are handled. Only ongoing enforcement work should remain in the steady-state tick.

## No Single-Use Extracted Helpers

- Do not extract a function from its only caller unless it has a clear, independently testable contract or is called from 2+ sites.
- A single-use helper called on the next line adds a call frame and forces a mental jump without earning its keep. Inline it.
- Sequential clusters of single-use helpers that all operate on the same data and are always called together should be merged into one coherent block.

## Prefer Table Lookups Over Pure-Mapping Functions

- If a function's output is determined entirely by its input with no state, and the input is from a small known set, use a constant lookup table instead of a function.

## Minimise Timer Deferral Depth

- Defer once out of a restricted execution context (e.g. secure callbacks), then execute synchronously. Do not stack sequential `C_Timer.After(0)` calls with no work between them.
- Each additional deferral adds a frame of latency. Maximum acceptable chain: secure-context deferral → batching scheduler → per-module throttle (3 levels).

## Error Recovery

- Critical state flags (e.g. `_layoutRunning`) must be cleared in a `pcall` guard or equivalent so that a single error does not permanently block future operations.

---

# Code Review

Your code will be reviewed by a distinguished engineer. Highly analytical who prioritises code excellence, impeccable design, elegance and simplicity, and is sceptical of poor-quality changes.

They are on special lookout for:
- Unused variables.
- Unnecessary assignments, guards, functions, boilerplate.
- No human-friendly and understandable comments for complex sections.
- Inefficiencies.
- Tight coupling and poor or no boundaries between components.
- Code duplication.
- Low reusability; poor future extensibility.
- Unnecessary complexity.
- Test coverage; edge cases; gaps.
- Performance — allocations on hot paths, avoidable work, stale caches.

Fewer lines but are meaningful (without being obtuse with formatting); simplicity; simple simple simple. Remove dead code; duplicated code; trivial wrappers; dead and needless type checking; remove anything that a senior software engineer would look at and raise their eye brows because it's stupid or unnecessary. Do not break functionality.

---

# Secret Values

Do not perform any operations except nil checking (including reads) on the following secret values except for passing them into other built-in functions:
- UnitPowerMax
- UnitPower
- UnitPowerPercent
- C_UnitAuras.GetUnitAuraBySpellID

Most functions have a CurveConstant parameter that will return an adjusted value. eg.

```lua
UnitPowerPercent("player", resource, false, CurveConstants.ScaleTo100)
```

## Restrictions

**The full list of technical restrictions for tainted code is as follows.**

- When an operation that is not allowed is performed, the result will be an immediate Lua error.
- Tainted code is allowed to store secret values in variables, upvalues, or as values in tables.
- Tainted code is allowed to pass secret values to Lua functions.
  - For C functions, an API must be explicitly marked up as accepting secrets from tainted callers.
- Tainted code is allowed to concatenate secret values that are strings or numbers.
  - Tainted code is additionally allowed to call APIs such as string.concat, string.format, and string.join with secret values.
- Tainted code is not allowed to perform arithmetic on secret values.
- Tainted code is not allowed to compare or perform boolean tests on secret values.
- Tainted code is not allowed to use the length operator (#) on secret values.
- Tainted code is not allowed to store secret values as keys in tables.
- Tainted code is not allowed to perform indexed access or assignment (secret["foo"] = 1) on secret values.
- Tainted code is not allowed to call secret values as-if they were functions.
- Querying the type of a secret value type(secret) returns its real type (ie. "string", "number", etc.).

### Secret tables

**For Lua tables, a few additional restrictions apply.**

- A table can be flagged such that indexed access of it will always yield a secret value.
- A table can be flagged as inaccessible to tainted code; any attempt to index, assign, measure, or iterate over such a table will trigger an immediate Lua error ("attempted to index a forbidden table").
- When untainted code stores a secret value as a table key, the table itself is irrevocably marked with both of the aforementioned flags.

**A few additional APIs exist to handle table secrecy.**

- canaccesstable(table) returns true if the calling function would not error if attempting to access the table.
