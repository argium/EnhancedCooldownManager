# SpellColors

Per-spell color customization for buff bars, backed by a multi-tier key system
with timestamp-based reconciliation across 4 key tiers.

## Architecture

```mermaid
classDiagram
    class SpellColorKeyType {
        +string keyType
        +string|number primaryKey
        +string spellName
        +number spellID
        +number cooldownID
        +number textureFileID
        +Matches(other) bool
        +Merge(other) SpellColorKey
        +ToString() string
        +ToArray() table
    }

    class KeyType ["KeyType.lua"] {
        +MakeKey(name, spellID, cooldownID, textureFileID) SpellColorKey
        +NormalizeKey(key) SpellColorKey
        +KeysMatch(left, right) bool
        +MergeKeys(base, other) SpellColorKey
    }

    class Store ["Store.lua"] {
        +SetConfigAccessor(accessor)
        +GetColorByKey(key) ECM_Color
        +GetColorForBar(frame) ECM_Color
        +GetAllColorEntries() table
        +SetColorByKey(key, color)
        +GetDefaultColor() ECM_Color
        +SetDefaultColor(color)
        +ResetColorByKey(key) bool×4
        +ReconcileAllKeys(keys) number
        +DiscoverBar(frame)
        +ClearDiscoveredKeys()
        +ClearCurrentSpecColors() number
    }

    class AceDB_Profile {
        buffBars.colors.byName
        buffBars.colors.bySpellID
        buffBars.colors.byCooldownID
        buffBars.colors.byTexture
    }

    KeyType --> SpellColorKeyType : creates
    Store --> KeyType : imports _-prefixed internals
    Store --> AceDB_Profile : reads/writes all 4 tiers
```

## Key Tier Priority

| Tier | Store Key | Identifier | Priority |
|------|-----------|------------|----------|
| 1 | `byName` | Spell name (string) | Highest |
| 2 | `bySpellID` | Spell ID (number) | |
| 3 | `byCooldownID` | Cooldown ID (number) | |
| 4 | `byTexture` | Texture file ID (number) | Lowest |

## Data Flow

```mermaid
sequenceDiagram
    participant BB as BuffBars
    participant SC as SpellColors
    participant DB as AceDB Profile

    BB->>SC: DiscoverBar(frame)
    Note over SC: Cache key in runtime discovery set

    BB->>SC: GetColorForBar(frame)
    SC->>SC: MakeKey(name, spellID, ...)
    SC->>DB: Lookup across 4 tiers (priority order)
    DB-->>SC: Best match
    SC-->>BB: ECM_Color or nil
```

## Public API

### KeyType.lua (`ECM.SpellColors`)

| Function | Description |
|----------|-------------|
| `MakeKey(name, spellID, cooldownID, textureFileID)` | Creates a normalized key from identifying values |
| `NormalizeKey(key)` | Normalizes a raw key table into a `SpellColorKeyType` |
| `KeysMatch(left, right)` | Returns true if two keys identify the same entry |
| `MergeKeys(base, other)` | Merges identifiers from matching keys |

### Store.lua (`ECM.SpellColors`)

| Function | Description |
|----------|-------------|
| `SetConfigAccessor(fn)` | Injects a config accessor (decouples from `db.profile`) |
| `GetColorByKey(key)` | Gets custom color for a normalized key |
| `GetColorForBar(frame)` | Gets custom color for a bar frame |
| `GetAllColorEntries()` | Returns all color entries for current class/spec |
| `SetColorByKey(key, color)` | Sets a custom color by key |
| `GetDefaultColor()` | Returns the default bar color |
| `SetDefaultColor(color)` | Sets the default bar color |
| `ResetColorByKey(key)` | Removes custom color from all tiers |
| `ReconcileAllKeys(keys)` | Reconciles a list of keys and repairs metadata |
| `DiscoverBar(frame)` | Registers a bar in the runtime discovery cache |
| `ClearDiscoveredKeys()` | Wipes the discovery cache |
| `ClearCurrentSpecColors()` | Wipes all colors for the current class/spec |
