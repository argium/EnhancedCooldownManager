# What to do when a task is “done”

## Sanity checks (WoW addon)
- Run a UI reload (`/reload`) and verify the addon loads without Lua errors.
- Open the options UI (`/ecm`) and confirm key controls still work.
- Validate behavior in/out of combat for any change that touches frames/layout.
- If touching aura/combat/instance logic, validate no secret-value errors occur.

## Layout/appearance checks (project-specific)
- Verify anchoring against Blizzard viewers (`EssentialCooldownViewer`, etc.).
- Verify bar chain behavior (`PowerBar` → `ResourceBar` → `RuneBar`) and BuffBar positioning.
- If changes affect hiding/fading, validate mount/rest/combat transitions.

## Logging
- Use `Util.Log()` for targeted debug while developing; keep noisy logs controlled by the addon’s debug setting.
