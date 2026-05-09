# Strict Re-Layering Refactor Prompt

Use this prompt when a code area has unclear boundaries, mixed responsibilities, or hard-to-follow dependencies.

```text
Please refactor `<TARGET_FOLDER>` into a clearer, thinner architecture with strict dependency direction.

First step, before proposing or editing anything:
- Analyze the relevant code in and around `<TARGET_FOLDER>`.
- Determine what the correct layers should be for this specific code.
- Do not assume layer names, count, or order from this prompt.
- Let the current responsibilities, public API, data flow, and external boundaries determine the architecture.

Primary goal:
- Reduce maintenance cost and improve readability.
- Do not merely rearrange complexity into nicer folders.
- Preserve public behavior and documented APIs unless I explicitly say otherwise.
- The result should make the core idea of this code area obvious to a new reader.

Discovery requirements:
1. Identify the current public/API surface.
2. Identify the current domain model or data model.
3. Identify external boundaries: framework APIs, platform APIs, UI APIs, IO, network, database clients, filesystem, globals, or other subsystem edges.
4. Identify orchestration/runtime/lifecycle code.
5. Identify pure helpers and reusable transformations.
6. Identify code that is doing translation/adaptation between concepts.
7. Identify duplicated paths, passthrough wrappers, dead branches, stale compatibility shims, and single-use abstractions.

Architecture requirements:
- Define a target dependency graph for this folder before moving code.
- Calls must move in one direction only according to that graph.
- Lower-level modules must not call higher-level modules.
- External/framework/platform calls must be isolated to explicit boundary modules.
- Public API modules must stay narrow and must not accumulate internal helper exports.
- Shared helpers must be pure unless there is a clear reason they cannot be.
- Translation code should be small and boring.
- Delete or inline unnecessary indirection while moving code.

Implementation requirements:
1. Inspect the current worktree and preserve existing user changes.
2. Move code by responsibility, not by old file shape.
3. Keep behavior stable unless a change is explicitly requested.
4. Avoid compatibility aliases for old internal paths unless public compatibility requires them.
5. Add architecture tests or source scans that enforce:
   - allowed dependency direction,
   - external API isolation,
   - public API narrowness,
   - no reintroduction of old flat internal namespaces.
6. Update load order, test helpers, and docs when files move.
7. Run the relevant tests and lint commands; report anything that cannot run.

Target-specific details:
- Target folder: `<TARGET_FOLDER>`
- Public behavior/API that must remain stable: `<PUBLIC_API>`
- External APIs or subsystem boundaries to isolate: `<EXTERNAL_BOUNDARIES>`
- Existing docs/load-order/test-helper files to update: `<SUPPORTING_FILES>`
- Required validation commands: `<VALIDATION_COMMANDS>`

Before implementing, state the inferred target architecture briefly, including:
- the named layers/modules,
- which dependencies are allowed,
- which dependencies are forbidden,
- which files are expected to move or be created.
Then implement the refactor and verify it.
```

## Example Invocation

```text
Use `.agents/prompts/strict-relayering.md` to refactor `Modules/AuraTracking`.

Keep public behavior stable for module registration and event outputs.
External boundaries include WoW aura APIs, event subscriptions, and saved variable writes.
Update `ARCHITECTURE.md` and any affected tests/load helpers.
Run `busted Tests` and `luacheck . -q`.
```
