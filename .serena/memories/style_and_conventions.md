# Current Style and Conventions

## Authoritative Docs
- `AGENTS.md` is the repo-wide agent rule source.
- `README.md` owns user-facing overview, install, and configuration.
- `ARCHITECTURE.md` owns addon module boundaries, init chain, event flow, and public APIs; keep it current for addon-level design changes.
- Library READMEs own each library's quick-start, API, schema, and tests: `LibSettingsBuilder`, `LibConsole`, `LibEvent`, and `LibLSMSettingsWidgets`.

## Mandatory Lua Rules
- Every Lua file starts with the standard Enhanced Cooldown Manager GPL v3 header.
- Target WoW Lua 5.1 only: no `goto`, labels, or `//`.
- Do not use forward declarations.
- Alias shared modules once at file scope when reused.
- Mutable state belongs on the owning instance as `self._field`, not file-level locals; private fields/methods use `_`.
- Prefer assertions for required parameters over guard/fallback branches.

## Architecture and Ownership
- Prefer the simplest production code that satisfies current supported runtime requirements. Do not add fallback paths, compatibility branches, or defensive adapters without a concrete supported environment.
- Keep one source of truth for shared state and derived values: derive once, store once, read everywhere.
- Prefer loose coupling via events, hooks, callbacks, or messages.
- Do not add duplicated utilities, trivial passthrough wrappers, or production-only indirection around fixed literals or stable signatures.
- Extract a helper/wrapper/abstraction only when it has an independently testable contract or at least two callers.
- Prefer constant lookup tables over pure mapping functions for small fixed domains.
- Remove dead code, stale fields, impossible branches, and unused locale strings.
- Clear critical state flags via `pcall` so one error cannot wedge later work.

## Runtime and Performance
- Never use `OnUpdate` or frame-rate tickers for feature logic; use event-driven updates plus one deferred timer when needed.
- Reuse hot-path tables with `wipe()`.
- Avoid snapshot-copying callback lists.
- Cancel superseded timers before scheduling replacement deferred work.
- Periodic setup must stop once all targets are handled.
- Defer once when leaving restricted contexts; avoid stacked `C_Timer.After(0)` chains.
- Guard hot-path debug logs with `if ECM.IsDebugEnabled() then`.

## Code Density
- Inline single-use locals into their sole call site.
- Generate repeated structural literals from a constructor; extract a thin wrapper only for repeated 2-3 call sequences.
- Prefer O(1) set lookups over linear scans for fixed load-time lists.
- Use compact single-line bodies for trivial functions.
- Do not assign fields to `nil` just to clear them; only assign fields that will be read later.
- Closures that differ only in one value should share a parameterized path.

## Tests and Stubs
- Be skeptical when changing tests to satisfy failures; the failure may be real.
- Test load order mirrors TOC load order.
- Test production code directly. Do not mirror/reimplement production logic in specs.
- Stub the canonical function, not a wrapper or alias. If a stub diverges from real behavior, fix the stub instead of adding production fallbacks.
- Reuse `Tests/TestHelpers.lua` before adding shared helpers.
- `StaticPopup_Show` stubs forward `(name, text1, text2, data)` and call `OnAccept(self, data)`.
- Shared confirm dialogs use `ECM.OptionUtil.MakeConfirmDialog(text)` with `data.onAccept`.

## Libraries, UI Templates, and Migrations
- Libraries stay self-contained: no ECM internals; tests and docs live with the library; public API changes are intentional and documented.
- Frame templates must be defined in `.xml`, not by Lua hooks on Blizzard functions such as `Settings.CreateElementInitializer`; XML virtual templates with `mixin="GlobalMixinName"` are multi-addon safe via LibStub.
- Migrations in `Migration.lua` are frozen snapshots and must not depend on live production code.
- A single style/metric has one owner. If a library renders a widget, the library owns dimensions, padding, fonts, and colors; callers must not redeclare matching defaults or pass redundant override knobs.

## Secret Values and Deprecated APIs
- Treat `UnitPowerMax`, `UnitPower`, `UnitPowerPercent`, and `C_UnitAuras.GetUnitAuraBySpellID` as secret values; see `repo/secret-values-and-deprecated-apis` for exact handling rules.
- Do not use deprecated Blizzard APIs, constants, aliases, or mixins listed in `repo/secret-values-and-deprecated-apis` for 12.0.5.