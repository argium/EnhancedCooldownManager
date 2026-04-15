# Current Style and Conventions

## Mandatory Repo Rules
- Every Lua file keeps the standard GPL copyright header.
- Keep `ARCHITECTURE.md` in sync with real architecture changes.
- Target WoW Lua 5.1 only; do not introduce post-5.1 features.

## State and Structure
- Mutable state belongs on the owning instance as `self._field`, not file-level locals.
- Prefix private methods/fields with `_`.
- Do not use forward declarations.
- Alias shared modules once at file scope when reused.
- Keep constants in `Constants.lua`; keep defaults in `Defaults.lua`.

## Runtime / Performance
- Never use `OnUpdate` or frame-rate tickers for feature logic; prefer event-driven work plus a single deferred timer when needed.
- Reuse tables on hot paths with `wipe()`.
- Cancel superseded timers before scheduling replacement deferred work.
- Guard hot-path debug logs with `if ECM.IsDebugEnabled() then`.
- Periodic setup work must stop once setup is complete.
- Defer once out of restricted contexts; avoid stacked `C_Timer.After(0)` chains.

## Architecture Boundaries
- Prefer loose coupling via events, hooks, callbacks, or messages.
- Maintain one source of truth for shared state / derived values.
- Do not add trivial passthrough wrappers or duplicate helpers.
- Remove dead code, stale fields, unused locale strings, and impossible branches.
- Shared confirm dialogs should use `ECM.OptionUtil.MakeConfirmDialog(text)` with `data.onAccept`.
- Migrations in `Migration.lua` are frozen snapshots and must not depend on live production code.

## Tests / Secrets
- Be skeptical about changing tests to satisfy failures.
- Test load order should mirror TOC load order.
- Reuse `Tests/TestHelpers.lua` before inventing new shared helpers.
- Treat `UnitPowerMax`, `UnitPower`, `UnitPowerPercent`, and `C_UnitAuras.GetUnitAuraBySpellID` as secret values; only pass them to APIs/built-ins that accept secrets.
