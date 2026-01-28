# Code Style & Conventions

## Formatting
- Encoding: UTF-8
- Indentation: 4 spaces (`.editorconfig`)
- Trim trailing whitespace; ensure final newline.

## Lua conventions
- Prefer clear naming over cleverness; avoid highly coupled designs.
- No upvalue caching (e.g., avoid `local math_floor = math.floor`).
- Use `assert()` / `error()` for invariants and early failure.
- Use `pcall` when interacting with Blizzard/third-party frames only where needed (e.g., fragile UI hooks).
- Avoid `type(x) == "function"` guards except where explicitly required for secret-value-safe checks (`issecretvalue`, `canaccessvalue`).

## Module boundaries
- Don’t reach into other modules’ internals; use exposed methods/events.
- Config is stored under `EnhancedCooldownManager.db.profile` with per-module subsections.

## Performance guidelines (WoW UI)
- Avoid unnecessary updates; prefer event-driven logic and throttling.
- Use pooling for frames where appropriate.
- Minimize CPU/memory usage in update paths.

## Blizzard frame architecture (project-specific)
- Cooldown viewer frames to consider:
  - `EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffIconCooldownViewer`, `BuffBarCooldownViewer`
- Bar stack convention:
  - `EssentialCooldownViewer` → `PowerBar` → `ResourceBar` → `RuneBar` → `BuffBarCooldownViewer`

## Debugging / utilities
- Logging: `Util.Log()` (structured debug logging).
- Pixel-perfect positioning: `Util.PixelSnap()`.

## Secret values (combat/instance restrictions)
- Some API returns may be “secret values” which cannot be safely compared/concatenated/converted.
- Use `issecretvalue(v)` / `canaccessvalue(v)` checks and `SafeGetDebugValue()` for debug strings.
- Avoid `C_UnitAuras` APIs using `spellId`; prefer `auraInstanceId` except where explicitly allowed by project guidance.
