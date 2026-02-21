# Running Tests

```sh
scoop install mingw luarocks
luarocks install busted
busted Tests
```

# Spell Color Key Semantics

Spell color keys are opaque objects created/normalized by `ECM.SpellColors` (`MakeKey`, `NormalizeKey`).

- Key priority: `spellName` > `spellID` > `cooldownID` > `textureFileID`.
- Identity matching:
  - Keys match when they share `spellName`, `spellID`, or `cooldownID`.
  - `textureFileID` is treated as a weak fallback and only matches when both keys are texture-only.
- Merge behavior:
  - `MergeKeys`/`key:Merge` combine known identifiers from both keys.
  - The merged key always re-selects primary key/type using the global priority order above.

Options/business logic should not implement key equality/merge directly; use key methods (`:Matches`, `:Merge`) or `ECM.SpellColors` key APIs.
