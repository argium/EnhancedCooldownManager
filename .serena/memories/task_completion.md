# Task Completion Checklist

## Validation Commands
- Addon tests: `busted Tests`
- Library tests: `busted --run libsettingsbuilder`, `busted --run libconsole`, `busted --run libevent`, `busted --run liblsmsettingswidgets`
- Lint: `luacheck . -q`

## When To Run Validation
- Treat validation as a pre-commit step, not an every-iteration step.
- Do not run the full test/lint suites while iterating unless they are needed to debug a specific issue.
- Before committing a change, updates to `Modules/`, `Helpers/`, `UI/`, and `ECM*.lua` must pass `busted Tests` and `luacheck . -q`.
- Before committing a library change, also run that library's dedicated test suite.

## Completion Checks
- Verify new constants live in `Constants.lua`.
- Keep the copyright header intact on all modified/new Lua files.
- Keep `ARCHITECTURE.md` current when architecture changes.
- Review for duplication, dead code, redundant guards/assignments, and avoidable allocations.
- Preserve loose coupling and single-source-of-truth ownership.
- Do not introduce `OnUpdate` loops or forward declarations.
