Use this prompt when a refactor plan or review identifies gaps between the intended implementation style and the code that was produced.

```text
Please apply the repository's default implementation standard to `<TARGET_SCOPE>` and continue until every identified gap is resolved.

Start by reading `AGENTS.md`, especially `Default Implementation Standard`, `Architecture`, `State and Style`, and `Tests`.

Primary goal:
- Make the implementation direct, explicit, and minimal.
- Preserve public behavior and documented public APIs unless I explicitly ask for a behavior change.
- Delete or inline needless indirection instead of adding new layers.
- Keep iterating until the plan is complete.

Discovery requirements:
1. Inspect the current worktree and recent commits so existing user changes are preserved.
2. Identify the plan items, review comments, or cleanup gaps that are still incomplete.
3. For each relevant file, identify:
   - the real owner of shared state, derived values, utilities, and rendering details,
   - table-attached helpers that should be local functions,
   - passthrough wrappers, aliases, fixed-literal mapping functions, and single-caller helpers,
   - duplicated decision logic, unnecessary temporary variables, and missing early returns,
   - local functions that accidentally rely on implicit `self`,
   - risky table iteration or callback execution that should use one direct `pcall` boundary,
   - tests that stub wrappers instead of canonical functions.

Implementation requirements:
1. Prefer direct calls to the real owner.
2. Remove wrappers and aliases that add no behavior.
3. Keep internal helpers file-local unless they are true public APIs, lifecycle hooks, or intentional shared test seams.
4. Pass owner context explicitly to local functions or make them methods.
5. Flatten conditionals and return early when it makes the main path clearer.
6. Inline single-use locals and helpers when doing so improves clarity.
7. Preserve behavior and test coverage; do not weaken tests to make the refactor pass.
8. Update `ARCHITECTURE.md` or library README files only when ownership, public API, or module boundaries change.

Validation requirements:
- Run the targeted tests for changed areas first.
- For root-level Lua, `Modules/`, or `UI/` changes, run:
  - `busted Tests`
  - `luacheck . -q`
- For `Libs/<Name>/` changes, also run that library's suite.
- Report any validation that cannot run and why.

Target-specific details:
- Target scope: `<TARGET_SCOPE>`
- Known gaps or plan items: `<GAPS>`
- Public behavior/API that must remain stable: `<PUBLIC_API>`
- Files likely involved: `<FILES>`
- Required validation commands: `<VALIDATION_COMMANDS>`

Before editing, state the checklist of remaining gaps. After editing, report the exact files changed and validation results.
```

## Example Invocation

```text
Use `.agents/prompts/default-refactor-cleanup.md` for the refactor cleanup in `Runtime.lua`, `SpellColors.lua`, `ECM.lua`, `BarMixin.lua`, and `Modules/ExternalBars.lua`.

Known gaps:
- remove table-attached passthrough wrappers,
- flatten duplicated fade/hidden decisions,
- remove scheduler flush indirection,
- simplify protected error-data iteration,
- make local aura abort owner context explicit,
- restore early returns in layout parameter calculation.

Keep public behavior stable. Run `busted Tests` and `luacheck . -q`.
```