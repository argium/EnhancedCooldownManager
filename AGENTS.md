- Be concise, professional, and honest.
- Use tables or Mermaid only when they materially improve clarity.
- Do not commit changes; the user commits manually.

---

# Validation

```sh
# Addon tests
busted Tests

# Library tests
busted --run libsettingsbuilder
busted --run libconsole
busted --run libevent
busted --run liblsmsettingswidgets

# Lint
luacheck . -q
```

- Changes to `Modules/`, `Helpers/`, `UI/`, and `ECM*.lua` must pass `busted Tests` and `luacheck . -q`.
- Library changes must also pass that library's dedicated test suite.

---

# Core Rules

<CopyrightHeader>
-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
</CopyrightHeader>

- Keep all constants in `ECM_Constants.lua`.
- New features and regression fixes in `Modules/`, `Helpers/`, `UI/`, and `ECM.lua` must include tests.
- All Lua files must include the standard copyright header.

## Lua / WoW Runtime

- Target WoW Lua 5.1; do not use post-5.1 features such as `goto`, labels, or `//`.
- Do not add compatibility shims for built-ins already present in WoW. If a shim exists only for `busted`, document that.
- Do not nil-check or wrap built-ins such as `issecretvalue`, `issecrettable`, or `canaccesstable`.

## Config, Events, and State

- Mutable state belongs on the owning instance (`self._field`), not file-level locals. Prefix private fields and methods with `_`.
- Do not use forward declarations. Alias shared modules once at file scope when reused.

## Performance

- Never use `OnUpdate` or frame-rate tickers; prefer event-driven updates plus a single deferred timer when needed.
- Reuse tables on hot paths with `wipe()`.
- Cancel superseded timers before scheduling new deferred work.
- Guard hot-path debug logging with `if ECM.IsDebugEnabled() then`.
- Avoid snapshot-copying callback lists; use zero-allocation iteration that tolerates removal.
- Periodic setup work must stop doing setup once all targets are handled.
- Defer once out of restricted contexts; avoid stacked `C_Timer.After(0)` chains.

## Architecture and Boundaries

- Prefer loose coupling via events, hooks, callbacks, or messages.
- Maintain a single source of truth for shared state and derived values: derive once, store once, read everywhere.
- Do not duplicate utilities or add trivial passthrough wrappers; extend the canonical owner instead.
- Do not extract single-use helpers unless they have a clear independently testable contract or 2+ callers.
- Prefer constant lookup tables over pure mapping functions for small fixed domains.
- Remove dead code, stale fields, impossible branches, and unused locale strings.
- Clear critical state flags with `pcall` or equivalent so one error cannot wedge later work.

## Tests, Libraries, and Migrations

- Be skeptical about changing tests to satisfy failures; the failure may be real.
- Test load order must mirror TOC load order.
- Stub the canonical function, not a wrapper or alias.
- Prefer testing live production code; avoid mirrored helper logic in specs.
- Reuse `Tests/TestHelpers.lua` before creating new shared test helpers.
- Test files mirror source paths; library tests stay under `Libs/<Name>/Tests/`.
- `StaticPopup_Show` stubs must forward `(name, text1, text2, data)` and call `OnAccept(self, data)`.
- Libraries must stay self-contained: no ECM internals; tests and docs live with the library; public API changes should be intentional and documented.
- Shared confirm dialogs use `ECM.OptionUtil.MakeConfirmDialog(text)` with `data.onAccept`.
- Migrations in `Helpers/Migration.lua` are frozen snapshots and must not depend on live production code.

---

# Review Heuristics

- Optimize for simple, explicit, maintainable code.
- Watch for unused variables, redundant guards or assignments, duplication, tight coupling, needless complexity, missing coverage, and avoidable allocations.

---

# Secret Values

- Treat `UnitPowerMax`, `UnitPower`, `UnitPowerPercent`, and `C_UnitAuras.GetUnitAuraBySpellID` as secret values.
- Only nil-check them or pass them to built-ins or APIs that accept secrets.
- Do not do arithmetic, comparisons, boolean tests, length, indexing, assignment, iteration, or use them as table keys.
- Storing secret values in locals, upvalues, or table values is allowed; concatenation and string formatting with string or number secrets is allowed.
- Secret tables may always yield secret values or be fully inaccessible; `canaccesstable(table)` only tells you whether access would be allowed.
