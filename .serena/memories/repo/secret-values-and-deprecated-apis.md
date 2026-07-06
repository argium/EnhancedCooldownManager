# Secret Values and Deprecated Blizzard APIs

## Secret Values
Treat `UnitPowerMax`, `UnitPower`, `UnitPowerPercent`, and `C_UnitAuras.GetUnitAuraBySpellID` as secret values.

Allowed handling:
- Nil-check them.
- Pass them to built-ins/APIs that accept secrets.
- Store them in locals/upvalues/table values.
- Concatenate or string-format string/number secrets.

Forbidden handling:
- Arithmetic, comparisons, boolean tests, length, indexing, assignment-derived logic, iteration, or use as table keys.
- Do not nil-check or wrap `issecretvalue`, `issecrettable`, or `canaccesstable`.
- Secret tables may yield secret values or be fully inaccessible; `canaccesstable(table)` only reports access, not contents.

## Deprecated Blizzard APIs (12.0.7)
Do not use the functions, constants, aliases, or mixins that Blizzard has deprecated; they are backward-compat shims and may be removed. Use the modern replacement from Blizzard source, typically a `C_*` namespace method or mixin method.

The complete denylist lives in `docs/BlizzardDeprecatedApis.md`; it is the single source of truth. Do not duplicate it here, or the two copies drift. Regenerate it for a new client build with `scripts/update-deprecated-apis.ps1 -Tag <version>` (see `.agents/prompts/update-deprecated-apis.md`).