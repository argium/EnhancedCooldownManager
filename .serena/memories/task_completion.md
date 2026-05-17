# Task Completion Checklist

## Required Validation
- For changes to `Modules/`, `UI/`, or root-level `*.lua`: run `busted Tests` and `luacheck . -q`.
- For changes under `Libs/<Name>/`: also run the matching library suite: `busted --run libsettingsbuilder`, `busted --run libconsole`, `busted --run libevent`, or `busted --run liblsmsettingswidgets`.

## Before Finishing
- Keep the standard GPL header intact on every new or modified Lua file.
- Keep `ARCHITECTURE.md` current for addon-level design changes.
- Keep the relevant library README current for library API/schema/test changes.
- Verify new constants live in `Constants.lua`; defaults live in `Defaults.lua`.
- Review for duplication, dead code, stale fields, redundant guards/fallbacks, unused locale strings, avoidable allocations, and needless abstractions.
- Preserve loose coupling and single-source-of-truth ownership.
- Do not introduce `OnUpdate`, frame-rate tickers, forward declarations, Lua post-5.1 syntax, deprecated Blizzard APIs, or invalid handling of secret values.
- For UI/library widgets, keep style metrics with the component/library owner; do not redeclare matching defaults from callers.

## Testing Judgment
- Treat validation as a pre-commit step, not something to run after every small iteration unless a specific failure is being debugged.
- Be skeptical about editing tests just to satisfy failures; production behavior may be wrong.
- If validation cannot be run, report that and explain the blocker.