- Be concise with your responses.
- Be professional but honest.
- Use mermaid diagrams and tables to explain complex concepts and architecture.

# Coding

- MANDATORY: **ALL constants** are to be stored in Constants.lua.
- MANDATORY: DO NOT UNDER ANY CIRCUMSTANCE NIL CHECK AND WRAP BUILT IN FUNCTIONS such as issecretvalue, issecrettable.
- MANDATORY: New features or regression fixes in `/Bars`, `/Modules`, `/UI`, and `ECM.lua` MUST include corresponding test cases
- MANDATORY: All lua files must include the standard copyright header
- Anything more than a small, targeted fix MUST perform a code review as described below as the final step after completing all tasks.
- Modules that utilize ModuleMixin, must use the live config accessors and never `mod.db` or `mod.db.profile` directly. NEVER create an intermediate table for profile/config.
  - `self:GetGlobalConfig()` for the `global` config block
  - `self:GetModuleConfig()` for the module's specific block
- Non-module code (Runtime, ECM.lua helpers) that needs the global config MUST use the shared standalone accessor (e.g. `ECM.GetGlobalConfig()`). NEVER inline `ns.Addon.db.profile.global` access.
- NEVER listen to the expensive `OnUpdate` event. This includes perpetual `C_Timer.NewTicker` at frame-rate intervals — prefer event-driven updates with a single deferred timer for animation tails.
- Do not use forward declarations.
- Do not add Lua version compatibility shims for built-ins that exist in WoW's Lua 5.1 runtime (e.g. `unpack`). If a shim is needed for the busted test runner (Lua 5.3+), add a comment explaining why.
- Mutable state (flags, caches) must be scoped to the owning module instance (`self._field`), not file-level locals. File-level locals are only for truly global singletons or constants.
- Do not create parallel table cloners or utility functions — reuse existing shared helpers (e.g. `ECM.CloneValue`).
- When debug logging or string serialization is called on a hot path (layout loops, tickers, per-bar styling), guard with `if isDebugEnabled() then` at the call site to avoid string concatenation overhead in production.
- Cross-module communication MUST use events/messages (LibEvent `SendMessage`/`RegisterMessage`), not monkey-patched callback fields on other modules' tables.

```sh
# Run tests
busted Tests

# Lint
luacheck . -q
```

<CopyrightHeader>
-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
</CopyrightHeader>

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

Fewer lines but are meaningful (without being obtuse with formatting); simplicity; simple simple simple. Remove dead code; duplicated code; trivial wrappers; dead and needless type checking; remove anything that a senior software engineer would look at and raise their eye brows because it's stupid or unnecessary. Do not break functionality.

# Architecture Invariants

These rules prevent recurring anti-patterns discovered during code review. Violations should be caught and fixed proactively.

## Single Source of Truth

- Each piece of shared state or derived value must have exactly one canonical accessor or derivation point. All other call sites must delegate to it.
- Do not create parallel accessor functions that reach the same underlying data through different paths. If a non-module caller needs access, expose a shared standalone function and alias it locally — don't reimplement the lookup.

## Derive Once, Read Everywhere

- Transforms or derived keys (e.g. name casing conventions) MUST be computed in exactly one place and stored for later use. Other code reads the stored result — never re-derives it.
- Authoritative ordered lists (module order, chain order) should live in Constants.

## No Dead Code

- Do not leave unused fields, stale type annotations, or cleanup of non-existent state in teardown/disable methods.
- If a function parameter or fallback branch can never execute (e.g. a fallback when the caller always provides the value), remove it.

## Periodic Work Must Degrade Gracefully

- Tickers or polling loops that perform setup tasks (hooking frames, discovering late-created objects) must track completion and skip the setup calls once all targets are handled. Only ongoing enforcement work should remain in the steady-state tick.

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
