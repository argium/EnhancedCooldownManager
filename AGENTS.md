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
| [`.agents/prompts/default-refactor-cleanup.md`](.agents/prompts/default-refactor-cleanup.md) | Reusable prompt for applying the default implementation standard to future refactors |

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

## Working Values

- Less code is better: prefer the smallest complete solution that preserves behavior.
- Keep implementation direct and explicit; avoid clever indirection, speculative abstractions, and compatibility paths without a current supported need.
- Prefer deleting duplication, dead code, and trivial wrappers over adding new layers.
- Document architecture changes where they help future maintainers understand ownership and flow.

## Default Implementation Standard

This is the default implementation style. Apply it first before adding abstractions, wrappers, fallbacks, or compatibility seams.

- Prefer direct calls to the real owner. Do not add wrapper methods, helper exports, or aliases unless they add behavior or preserve a documented public API.
- Keep file-local helpers file-local. Public tables expose public APIs only; internal helpers are not exported for symmetry, organization, or test access.
- Make ownership explicit at the call site. Local functions that operate on an instance take the owner as a parameter or become instance methods; they must not rely on implicit `self`.
- Flatten control flow with early returns and single decision blocks. Do not compute temporary results only to return them later when an immediate return is clearer.
- Use one protected operation around risky table iteration or callback execution instead of wrapping every iterator step in helper indirection.
- Collapse single-use locals, single-caller helpers, fixed-literal mapping functions, and stale compatibility branches into their call sites.
- When a plan identifies cleanup gaps, keep iterating until every item is either implemented, explicitly documented as intentionally deferred, or rejected with a clear reason.

All Lua files start with:

```lua
-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
```

## Architecture

- Prefer the simplest production code for current supported runtimes. No fallback paths, compatibility branches, defensive adapters, or built-in shims without a concrete supported environment that needs them.
- Do not nil-guard methods, fields, or globals that are guaranteed to exist on current Retail (e.g., `Frame:GetRegions`, `Region:IsObjectType`, `Texture:GetMaskTexture`/`RemoveMaskTexture`, `:Hide`, `YES`/`NO`, `C_EditMode`). Call them directly. Guard only against optional third-party addons (e.g., `DevTool`), genuinely polymorphic shapes, or runtime data that may be absent.
- Keep one owner for shared state, derived values, utility functions, style metrics, and widget rendering details.
- Use loose coupling through events, hooks, callbacks, or messages.
- Do not add trivial passthrough wrappers, fixed-literal indirection, or single-caller abstractions without an independently testable contract.
- Treat passthrough methods as an anti-pattern. If a method only forwards to another function, table, or shared helper without adding real behavior, delete it or call the real owner directly.
- Prefer constant lookup tables and `O(1)` sets over mapping functions or linear scans for fixed load-time domains.
- Remove dead code, stale fields, impossible branches, unused upvalues, and unused locale strings.
- Clear critical state flags via `pcall` so one error cannot wedge later work.

## State and Style

- Mutable state belongs on the owning instance (`self._field`), not file-level locals. Prefix private fields/methods with `_`.
- No forward declarations; reorder code instead. Alias shared modules once at file scope.
- Functions used only within one file stay local. Do not attach file-local helpers to module tables just for organization, symmetry, or test access.
- Attaching a function to a module table without using `self` is a smell. If it is also `_`-prefixed, that is a strong signal the function should be a `local function` instead of a table field.
- Only attach functions to a module table when they are true cross-file APIs, lifecycle hooks, or intentionally shared test seams.
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
- Do not preserve or introduce table-attached helper methods purely so specs can call them. Prefer testing the real public flow, or the actual shared owner of the logic.
- Stub the canonical function, not a wrapper or alias. If a stub diverges from real behavior, fix the stub.
- Do not guard production APIs only to satisfy tests. If an API exists in the supported runtime/load order, tests must stub it.
- Reuse `Tests/TestHelpers.lua` before creating new shared helpers.
- `StaticPopup_Show` stubs forward `(name, text1, text2, data)` and call `OnAccept(self, data)`.
- Shared confirm dialogs use `ECM.OptionUtil.MakeConfirmDialog(text)` with `data.onAccept`.

## Popup Dialogs

- Build option popups through shared helpers (`ECM.OptionUtil.MakeConfirmDialog` or `ECM.OptionUtil.MakeTextInputDialog`) unless a dialog needs a truly custom frame.
- Use explicit, human-friendly action labels. Prefer macOS-style verbs such as `Delete` / `Don't delete`, `Create` / `Don't create`, `Rename` / `Don't rename`, and `Remove` / `Don't remove`.
- Do not use generic `OK`, `Cancel`, `Yes`, or `No` for destructive, mutating, or named option actions.
- Dialog prompt text should name the affected object where possible, and button text should describe the action rather than the implementation.

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
