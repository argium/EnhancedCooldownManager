IMPORTANT: Run initialize serena tool, if it's available.
Use Serena for codebase text search and source reading by default. Prefer Serena `search_for_pattern`, `get_symbols_overview`, `find_symbol`, and `read_file` for inspecting repository files. Use shell commands for Git metadata, diffs, validation commands, and cases where Serena cannot provide the needed result.

# Documentation Map

Authoritative source for repo-wide agent rules. Topic-specific docs own their own surface; do not duplicate their content here.

| Doc | Owns |
|---|---|
| [README.md](README.md) | User-facing overview, install, configuration |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Module boundaries, init chain, event flow, public APIs |
| [docs/BlizzardDeprecatedApis.md](docs/BlizzardDeprecatedApis.md) | Deprecated Blizzard API denylist |
| [Libs/LibSettingsBuilder/README.md](Libs/LibSettingsBuilder/README.md) | Settings builder API and schema |
| [Libs/LibConsole/README.md](Libs/LibConsole/README.md) | Slash-command library |
| [Libs/LibEvent/README.md](Libs/LibEvent/README.md) | Embeddable event system |
| [Libs/LibLSMSettingsWidgets/README.md](Libs/LibLSMSettingsWidgets/README.md) | LSM picker templates |

Keep `ARCHITECTURE.md` current for addon-level design changes; each library's README owns its quick-start, API, and tests.

---

# Validation

```sh
busted Tests
busted --run libsettingsbuilder
busted --run libconsole
busted --run libevent
busted --run liblsmsettingswidgets
luacheck . -q
```

- Changes to `Modules/`, `UI/`, or root-level `*.lua` must pass `busted Tests` and `luacheck . -q`.
- Changes under `Libs/<Name>/` must also pass that library's suite.

---

# Core Rules

All Lua files start with:

```lua
-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
```

## Architecture

- Prefer the simplest production code for current supported runtimes. No fallback paths, compatibility branches, defensive adapters, or built-in shims without a concrete supported environment that needs them.
- Keep one owner for shared state, derived values, utility functions, style metrics, and widget rendering details.
- Use loose coupling through events, hooks, callbacks, or messages.
- Do not add trivial passthrough wrappers, fixed-literal indirection, or single-caller abstractions without an independently testable contract.
- Prefer constant lookup tables and `O(1)` sets over mapping functions or linear scans for fixed load-time domains.
- Remove dead code, stale fields, impossible branches, unused upvalues, and unused locale strings.
- Clear critical state flags via `pcall` so one error cannot wedge later work.

## State and Style

- Mutable state belongs on the owning instance (`self._field`), not file-level locals. Prefix private fields/methods with `_`.
- No forward declarations; reorder code instead. Alias shared modules once at file scope.
- Prefer assertions for required parameters over guards and fallbacks.
- Target WoW Lua 5.1: no `goto`, labels, `//`, bitwise operators, or newer Lua syntax.
- Inline single-use locals into their sole call site. Compact trivial function bodies to one line when readable.
- Generate repeated structural literals from a constructor; extract thin wrappers only for repeated 2-3 call sequences.
- Do not assign fields to `nil` to "clear" them unless the nil value is read later.
- Closures differing only by one value should share a parameterized path.

## Runtime and Performance

- Never use `OnUpdate` or frame-rate tickers. Use event-driven updates plus one deferred timer when needed.
- Reuse hot-path tables with `wipe()` and avoid snapshot-copying callback lists.
- Cancel superseded timers before scheduling new deferred work; periodic setup must stop once all targets are handled.
- Defer once when leaving restricted contexts; do not stack `C_Timer.After(0)` chains.
- Guard hot-path debug logs with `if ECM.IsDebugEnabled() then`.
- Frame templates belong in `.xml`, not Lua hooks on Blizzard functions like `Settings.CreateElementInitializer`; XML virtual templates with `mixin="GlobalMixinName"` are multi-addon safe via LibStub.

## Tests

- Existing tests are behavioral specifications. Do not invert, weaken, or rewrite a test unless the old behavior is explicitly obsolete; preserve equivalent coverage for the new behavior.
- Test load order mirrors TOC load order. Test files mirror source paths; library tests live under `Libs/<Name>/Tests/`.
- Test production code directly. Do not mirror production logic in specs.
- Stub the canonical function, not a wrapper or alias. If a stub diverges from real behavior, fix the stub.
- Do not guard production APIs only to satisfy tests. If an API exists in the supported runtime/load order, tests must stub it.
- Reuse `Tests/TestHelpers.lua` before creating new shared helpers.
- `StaticPopup_Show` stubs forward `(name, text1, text2, data)` and call `OnAccept(self, data)`.
- Shared confirm dialogs use `ECM.OptionUtil.MakeConfirmDialog(text)` with `data.onAccept`.

## Libraries and Migrations

- Libraries stay self-contained: no ECM internals; tests and docs live with the library; public API changes are intentional and documented.
- Migrations in `Migration.lua` are frozen snapshots and must not depend on live production code.

---

# Review Heuristics

Optimize for simple, explicit, maintainable code. Prioritize correctness, taint/security, architecture, duplication, and style. Watch for unused variables, redundant guards, tight coupling, needless complexity, missing coverage, and avoidable allocations.

---

# Secret Values

Treat `UnitPowerMax`, `UnitPower`, `UnitPowerPercent`, and `C_UnitAuras.GetUnitAuraBySpellID` as secret values.

- Only nil-check them or pass them to built-ins/APIs that accept secrets.
- No arithmetic, comparisons, boolean tests, length, indexing, assignment-derived logic, iteration, or use as table keys.
- Storing in locals/upvalues/table values is fine; concatenation and string formatting with string/number secrets is fine.
- Secret tables may yield secret values or be fully inaccessible; `canaccesstable(table)` only reports access, not contents.
- Do not nil-check or wrap built-ins like `issecretvalue`, `issecrettable`, or `canaccesstable`.

---

# Deprecated Blizzard APIs

Do not use deprecated Blizzard functions, constants, aliases, or mixins. See [docs/BlizzardDeprecatedApis.md](docs/BlizzardDeprecatedApis.md) for the 12.0.5 denylist and replacement-source guidance.
