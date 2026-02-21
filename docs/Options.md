# Options.lua Developer Guide

This document describes how to write new options for the Enhanced Cooldown Manager addon.

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [File Structure](#file-structure)
3. [Widget Types](#widget-types)
4. [Common Patterns](#common-patterns)
5. [Helper Functions](#helper-functions)
6. [Order Conventions](#order-conventions)
7. [Config Path Requirements](#config-path-requirements)
8. [Complete Examples](#complete-examples)

---

## Architecture Overview

The options system uses **AceConfig-3.0** to build a hierarchical tree-based UI. The structure is:

```
Enhanced Cooldown Manager (root)
├── General
├── Power Bar
├── Resource Bar
├── Rune Bar
├── Buff Bars
├── Item Icons
├── Profile (Import/Export, Profile Management)
└── About
```

### How It Works

1. **Option Tables**: Each section has a generator function (e.g., `PowerBarOptionsTable()`) that returns an AceConfig-compatible table
2. **Main Table**: `GetOptionsTable()` combines all sections into a tree structure
3. **Registration**: Options are registered with AceConfigRegistry and linked to Blizzard's settings UI
4. **Database Access**: Options write profile settings either directly in `UI/Options.lua` or through module-owned options builders (for example `Modules/ItemIcons.lua`)

---

## File Structure

```lua
-- 1. Dependencies and Constants
local ECM = ns.Addon

-- 2. Constants
local SIDEBAR_BG_COLOR = { r = 0.1, g = 0.1, b = 0.1, a = 0.9 }

-- 3. Helper Functions (utilities, path operations, etc.)
local function IsValueChanged(path) ... end
local function MakeResetHandler(path, refreshFunc) ... end

-- 4. Section Generator Functions
local function PowerBarOptionsTable() ... end
local function ResourceBarOptionsTable() ... end
-- Item Icons options are built in Modules/ItemIcons.lua:
-- ItemIcons:GetOptionsTable(db.profile.itemIcons)

-- Item Icons options behavior:
-- - Options are split into three groups:
--   - Basic Settings: Enable item icons
--   - Items: Show first trinket, Show second trinket
--   - Consumables: Show health potions, Show combat potions, Show healthstone
-- - "Enable item icons" disables/enables all other controls in the Item Icons section.

-- 5. Main Options Table
local function GetOptionsTable() ... end

-- 6. Module Lifecycle
function Options:OnInitialize() ... end
```

---

## Widget Types

### 1. Toggle (Checkbox)

```lua
myToggle = {
    type = "toggle",
    name = "Enable feature",
    desc = "Tooltip text shown on hover",  -- optional
    order = 1,
    width = "full",  -- or "normal", "double", "half", numeric value
    get = function() return db.profile.myModule.enabled end,
    set = function(_, val)
        db.profile.myModule.enabled = val
        ECM.ScheduleLayoutUpdate(0)  -- Trigger layout update
    end,
}
```

**Notes:**
- Use `width = "full"` for toggles that span the whole width
- Always call `ECM.ScheduleLayoutUpdate(0)` in `set` if the change affects layout

### 2. Range (Slider)

```lua
myRange = {
    type = "range",
    name = "Bar Height",
    desc = "Height of the bar in pixels",
    order = 2,
    width = "double",
    min = 0,
    max = 40,
    step = 1,
    get = function() return db.profile.myModule.height or 0 end,
    set = function(_, val)
        -- Store nil for default value (0 in this case)
        db.profile.myModule.height = val > 0 and val or nil
        ECM.ScheduleLayoutUpdate(0)
    end,
}
```

**Notes:**
- Use `width = "double"` for sliders
- Store `nil` for default/zero values to keep config clean
- Include a reset button (see Common Patterns)

### 3. Select (Dropdown)

```lua
mySelect = {
    type = "select",
    name = "Bar Texture",
    order = 3,
    width = "double",
    dialogControl = "LSM30_Statusbar",  -- For LibSharedMedia integration
    values = GetLSMStatusbarValues,  -- Function or table
    get = function() return db.profile.global.texture end,
    set = function(_, val)
        db.profile.global.texture = val
        ECM.ScheduleLayoutUpdate(0)
    end,
}
```

**Font dropdown using SharedMedia widgets:**
```lua
myFontSelect = {
    type = "select",
    name = "Font",
    order = 4,
    width = "double",
    dialogControl = "LSM30_Font",  -- Requires AceGUI-3.0-SharedMediaWidgets
    values = function()
        if AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.font then
            return AceGUIWidgetLSMlists.font
        end
        return GetLSMValues("font", "Expressway")
    end,
    get = function() return db.profile.global.font end,
    set = function(_, val)
        db.profile.global.font = val
        ECM.ScheduleLayoutUpdate(0)
    end,
}
```

`LSM30_Font` renders each option name in its own font, which is ideal for global font-face selection.

**Values as table:**
```lua
values = {
    [ECM.Constants.ANCHORMODE_CHAIN] = "Position Automatically",
    [ECM.Constants.ANCHORMODE_FREE] = "Free Positioning",
}
```

**Values as function:**
```lua
local function GetMyValues()
    return {
        option1 = "Display Name 1",
        option2 = "Display Name 2",
    }
end

-- In widget:
values = GetMyValues,
```

### 4. Color Picker

```lua
myColor = {
    type = "color",
    name = "Border color",
    order = 4,
    width = "small",
    hasAlpha = true,  -- Include alpha channel
    get = function()
        local c = db.profile.myModule.color
        return c.r, c.g, c.b, c.a  -- Return 4 values
    end,
    set = function(_, r, g, b, a)
        db.profile.myModule.color = { r = r, g = g, b = b, a = a }
        ECM.ScheduleLayoutUpdate(0)
    end,
}
```

**Notes:**
- `get` must return 4 separate values (r, g, b, a)
- `set` receives 4 separate parameters
- Store as table with `r`, `g`, `b`, `a` keys

### 5. Execute (Button)

```lua
myButton = {
    type = "execute",
    name = "Reset All",
    desc = "Resets all settings to defaults",
    order = 5,
    width = "full",
    confirm = true,  -- Show confirmation dialog
    confirmText = "Are you sure you want to reset?",
    func = function()
        db:ResetProfile()
        ReloadUI()
    end,
}
```

**For reset buttons:**
```lua
myReset = {
    type = "execute",
    name = "X",
    order = 6,
    width = 0.3,  -- Small button next to slider
    hidden = function() return not IsValueChanged("myModule.height") end,
    func = MakeResetHandler("myModule.height"),
}
```

### 6. Description (Text)

```lua
myDescription = {
    type = "description",
    name = "This is explanatory text that appears in the UI.",
    order = 1,
    fontSize = "medium",  -- or "small", "large"
}
```

**For spacing:**
```lua
spacer = {
    type = "description",
    name = " ",
    order = 2.5,
}
```

### 7. Group (Section Container)

```lua
myGroup = {
    type = "group",
    name = "Basic Settings",
    inline = true,  -- Show as inline box, false for tree node
    order = 1,
    args = {
        -- Child widgets go here
        toggle1 = { ... },
        range1 = { ... },
    },
}
```

---

## Common Patterns

### Pattern 1: Range with Reset Button

```lua
-- Description
heightDesc = {
    type = "description",
    name = "Override the default bar height. Set to 0 to use the global default.",
    order = 1,
},

-- Range slider
height = {
    type = "range",
    name = "Height Override",
    order = 2,
    width = "double",
    min = 0,
    max = 40,
    step = 1,
    get = function() return db.profile.myModule.height or 0 end,
    set = function(_, val)
        db.profile.myModule.height = val > 0 and val or nil
        ECM.ScheduleLayoutUpdate(0)
    end,
},

-- Reset button (appears next to slider)
heightReset = {
    type = "execute",
    name = "X",
    order = 3,
    width = 0.3,
    hidden = function() return not IsValueChanged("myModule.height") end,
    func = MakeResetHandler("myModule.height"),
},
```

**Key points:**
- Description uses order N
- Slider uses order N+1, width "double"
- Reset uses order N+2, width 0.3
- Reset is hidden when value equals default

### Pattern 2: Conditional Visibility

```lua
-- Widget only visible in Free positioning mode
width = {
    type = "range",
    name = "Width",
    order = 4,
    width = "double",
    min = 100,
    max = 600,
    step = 10,
    hidden = function() return not IsAnchorModeFree(db.profile.myModule) end,
    get = function() return db.profile.myModule.width or ECM.Constants.DEFAULT_BAR_WIDTH end,
    set = function(_, val)
        db.profile.myModule.width = val
        ECM.ScheduleLayoutUpdate(0)
    end,
},
```

**Reset button must match visibility:**
```lua
widthReset = {
    type = "execute",
    name = "X",
    order = 5,
    width = 0.3,
    hidden = function()
        return not IsAnchorModeFree(db.profile.myModule) or not IsValueChanged("myModule.width")
    end,
    func = MakeResetHandler("myModule.width"),
},
```

### Pattern 3: Disabled State

```lua
borderThickness = {
    type = "range",
    name = "Border width",
    order = 8,
    width = "small",
    min = 1,
    max = 10,
    step = 1,
    disabled = function() return not db.profile.myModule.border.enabled end,
    get = function() return db.profile.myModule.border.thickness end,
    set = function(_, val)
        db.profile.myModule.border.thickness = val
        ECM.ScheduleLayoutUpdate(0)
    end,
},
```

**Notes:**
- Use `disabled` for widgets that require another setting to be enabled
- Use `hidden` for widgets that only apply in certain modes

### Pattern 4: Position Mode Selector

```lua
modeSelector = {
    type = "select",
    name = "",
    order = 2,
    width = "full",
    dialogControl = "ECM_PositionModeSelector",  -- Custom widget
    values = POSITION_MODE_TEXT,
    get = function()
        return db.profile.myModule.anchorMode
    end,
    set = function(_, val)
        ApplyPositionModeToBar(db.profile.myModule, val)
        ECM.ScheduleLayoutUpdate(0)
    end,
},
```

### Pattern 5: Border Settings Group

```lua
border = {
    type = "group",
    name = "Border",
    inline = true,
    order = 2,
    args = {
        enabled = {
            type = "toggle",
            name = "Show border",
            order = 1,
            width = "full",
            get = function() return db.profile.myModule.border.enabled end,
            set = function(_, val)
                db.profile.myModule.border.enabled = val
                ECM.ScheduleLayoutUpdate(0)
            end,
        },
        thickness = {
            type = "range",
            name = "Border width",
            order = 2,
            width = "small",
            min = 1,
            max = 10,
            step = 1,
            disabled = function() return not db.profile.myModule.border.enabled end,
            get = function() return db.profile.myModule.border.thickness end,
            set = function(_, val)
                db.profile.myModule.border.thickness = val
                ECM.ScheduleLayoutUpdate(0)
            end,
        },
        color = {
            type = "color",
            name = "Border color",
            order = 3,
            width = "small",
            hasAlpha = true,
            disabled = function() return not db.profile.myModule.border.enabled end,
            get = function()
                local c = db.profile.myModule.border.color
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                db.profile.myModule.border.color = { r = r, g = g, b = b, a = a }
                ECM.ScheduleLayoutUpdate(0)
            end,
        },
    },
},
```

---

## Helper Functions

### IsValueChanged(path)

Checks if a config value differs from its default.

```lua
local changed = IsValueChanged("myModule.height")
```

**Usage:**
- In `hidden` functions for reset buttons
- Path uses dot notation: `"module.subkey.value"`

### MakeResetHandler(path, refreshFunc)

Creates a reset button handler that:
1. Resets value to default
2. Calls optional refresh function
3. Triggers layout update
4. Notifies AceConfig to refresh UI

```lua
func = MakeResetHandler("myModule.height")
```

**With custom refresh:**
```lua
func = MakeResetHandler("myModule.height", function()
    print("Height was reset")
end)
```

### GetNestedValue(table, path)

Gets a value using dot-separated path.

```lua
local value = GetNestedValue(db.profile, "powerBar.border.thickness")
```

### SetNestedValue(table, path, value)

Sets a value using dot-separated path.

```lua
SetNestedValue(db.profile, "powerBar.border.thickness", 2)
```

### GetLSMStatusbarValues()

Returns LibSharedMedia statusbar texture options.

```lua
values = GetLSMStatusbarValues,
```

### MakePositioningSettingsArgs(configPath, options)

Generates positioning settings (width, offsetX, offsetY with reset buttons) for a bar.

**Parameters:**
- `configPath` (string): Config path like "powerBar", "buffBars"
- `options` (table, optional): Customization options
  - `includeOffsets` (boolean): Include offsetX/offsetY (default: true)
  - `widthLabel` (string): Label for width slider (default: "Width")
  - `widthDesc` (string): Description for width setting
  - `offsetXDesc` (string): Description for offsetX setting
  - `offsetYDesc` (string): Description for offsetY setting

**Returns:** Table of widget args to merge into positioning group

**Example:**
```lua
positioningSettings = (function()
    local positioningArgs = {
        modeDesc = { ... },
        modeSelector = { ... },
        spacer1 = { ... },
    }

    -- Add width, offsetX, offsetY settings
    local positioningSettings = MakePositioningSettingsArgs("powerBar")
    for k, v in pairs(positioningSettings) do
        positioningArgs[k] = v
    end

    return {
        type = "group",
        name = "Positioning",
        inline = true,
        order = 3,
        args = positioningArgs,
    }
end)()
```

**Without offsets (BuffBars):**
```lua
local positioningSettings = MakePositioningSettingsArgs("buffBars", {
    includeOffsets = false,
    widthLabel = "Buff Bar Width",
    widthDesc = "\nWidth of the buff bars when automatic positioning is disabled.",
})
```

---

## Order Conventions

Use consistent ordering to maintain a predictable UI layout:

### Module-Level Groups (in GetOptionsTable)

```lua
args = {
    general = GeneralOptionsTable(),      -- order = 1
    powerBar = PowerBarOptionsTable(),    -- order = 2
    resourceBar = ResourceBarOptionsTable(), -- order = 3
    runeBar = RuneBarOptionsTable(),      -- order = 4
    auraBars = AuraBarsOptionsTable(),    -- order = 5
    itemIcons = ItemIconsOptionsTable(),  -- order = 6
    profile = ProfileOptionsTable(),      -- order = 7
    about = AboutOptionsTable(),          -- order = 8
}
```

### Standard Module Structure

Each module options table follows this order:

```lua
args = {
    basicSettings = {     -- order = 1
        type = "group",
        name = "Basic Settings",
        inline = true,
        order = 1,
        args = { ... }
    },
    border = {           -- order = 2
        type = "group",
        name = "Border",
        inline = true,
        order = 2,
        args = { ... }
    },
    positioningSettings = { -- order = 3
        type = "group",
        name = "Positioning",
        inline = true,
        order = 3,
        args = { ... }
    },
    tickMarks = { ... }, -- order = 4 (if applicable)
    colors = { ... },    -- order = 5 (if applicable)
}
```

### Within a Group

```lua
args = {
    -- 1. Description (if needed)
    heightDesc = {
        order = 1,
    },

    -- 2. Main control
    height = {
        order = 2,
    },

    -- 3. Reset button (if applicable)
    heightReset = {
        order = 3,
    },

    -- 4. Optional spacer
    spacer1 = {
        order = 3.5,  -- Use decimals for insertions
    },

    -- 5. Next setting
    width = {
        order = 4,
    },
}
```

**Order Guidelines:**
- Leave gaps (1, 10, 20, 30...) when settings may grow
- Use decimals (2.5, 3.5) for spacers or insertions
- Group related settings with consecutive orders
- Description → Control → Reset is always in sequence

---

## Config Path Requirements

**CRITICAL:** Always use the correct config path based on where settings are defined in `Defaults.lua`.

### Global Settings

Settings under `profile.global` in Defaults.lua:

```lua
-- ✅ CORRECT
get = function() return db.profile.global.hideWhenMounted end,
set = function(_, val)
    db.profile.global.hideWhenMounted = val
    ECM.ScheduleLayoutUpdate(0)
end,

-- Reset button
hidden = function() return not IsValueChanged("global.hideWhenMounted") end,
func = MakeResetHandler("global.hideWhenMounted"),
```

```lua
-- ❌ WRONG - Missing .global
get = function() return db.profile.hideWhenMounted end,
```

### Module-Specific Settings

Settings under `profile.moduleName` in Defaults.lua:

```lua
-- ✅ CORRECT
get = function() return db.profile.powerBar.height end,
set = function(_, val)
    db.profile.powerBar.height = val
    ECM.ScheduleLayoutUpdate(0)
end,

-- Reset button
hidden = function() return not IsValueChanged("powerBar.height") end,
func = MakeResetHandler("powerBar.height"),
```

**Verification Steps:**
1. Find the setting in `Defaults.lua`
2. Note its full path (e.g., `profile.global.texture` or `profile.powerBar.height`)
3. Use the same path in Options.lua
4. Path in `IsValueChanged` and `MakeResetHandler` omits `profile.` prefix

---

## Complete Examples

### Example 1: Simple Toggle with Description

```lua
local function MyModuleOptionsTable()
    local db = ns.Addon.db
    return {
        type = "group",
        name = "My Module",
        order = 10,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    enabledDesc = {
                        type = "description",
                        name = "Enable this module to show additional information.",
                        order = 1,
                    },
                    enabled = {
                        type = "toggle",
                        name = "Enable my module",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.myModule.enabled end,
                        set = function(_, val)
                            db.profile.myModule.enabled = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                },
            },
        },
    }
end
```

### Example 2: Full Bar Configuration

```lua
local function MyBarOptionsTable()
    local db = ns.Addon.db
    return {
        type = "group",
        name = "My Bar",
        order = 10,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable my bar",
                        order = 1,
                        width = "full",
                        get = function() return db.profile.myBar.enabled end,
                        set = function(_, val)
                            db.profile.myBar.enabled = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    heightDesc = {
                        type = "description",
                        name = "\nHeight of the bar in pixels.",
                        order = 2,
                    },
                    height = {
                        type = "range",
                        name = "Height",
                        order = 3,
                        width = "double",
                        min = 10,
                        max = 40,
                        step = 1,
                        get = function() return db.profile.myBar.height end,
                        set = function(_, val)
                            db.profile.myBar.height = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 4,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("myBar.height") end,
                        func = MakeResetHandler("myBar.height"),
                    },
                },
            },
            border = {
                type = "group",
                name = "Border",
                inline = true,
                order = 2,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Show border",
                        order = 1,
                        width = "full",
                        get = function() return db.profile.myBar.border.enabled end,
                        set = function(_, val)
                            db.profile.myBar.border.enabled = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    thickness = {
                        type = "range",
                        name = "Border width",
                        order = 2,
                        width = "small",
                        min = 1,
                        max = 10,
                        step = 1,
                        disabled = function() return not db.profile.myBar.border.enabled end,
                        get = function() return db.profile.myBar.border.thickness end,
                        set = function(_, val)
                            db.profile.myBar.border.thickness = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    color = {
                        type = "color",
                        name = "Border color",
                        order = 3,
                        width = "small",
                        hasAlpha = true,
                        disabled = function() return not db.profile.myBar.border.enabled end,
                        get = function()
                            local c = db.profile.myBar.border.color
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            db.profile.myBar.border.color = { r = r, g = g, b = b, a = a }
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                },
            },
            positioningSettings = {
                type = "group",
                name = "Positioning",
                inline = true,
                order = 3,
                args = {
                    modeDesc = {
                        type = "description",
                        name = "Choose how the bar is positioned.",
                        order = 1,
                    },
                    modeSelector = {
                        type = "select",
                        name = "",
                        order = 2,
                        width = "full",
                        dialogControl = "ECM_PositionModeSelector",
                        values = POSITION_MODE_TEXT,
                        get = function()
                            return db.profile.myBar.anchorMode
                        end,
                        set = function(_, val)
                            ApplyPositionModeToBar(db.profile.myBar, val)
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    widthDesc = {
                        type = "description",
                        name = "\nWidth when free positioning is enabled.",
                        order = 3,
                        hidden = function() return not IsAnchorModeFree(db.profile.myBar) end,
                    },
                    width = {
                        type = "range",
                        name = "Width",
                        order = 4,
                        width = "double",
                        min = 100,
                        max = 600,
                        step = 10,
                        hidden = function() return not IsAnchorModeFree(db.profile.myBar) end,
                        get = function() return db.profile.myBar.width or ECM.Constants.DEFAULT_BAR_WIDTH end,
                        set = function(_, val)
                            db.profile.myBar.width = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    widthReset = {
                        type = "execute",
                        name = "X",
                        order = 5,
                        width = 0.3,
                        hidden = function()
                            return not IsAnchorModeFree(db.profile.myBar) or not IsValueChanged("myBar.width")
                        end,
                        func = MakeResetHandler("myBar.width"),
                    },
                },
            },
        },
    }
end
```

### Example 3: Dynamic Options (BuffBars Spell Color List)

For options that must be generated at runtime based on data:

```lua
local function GenerateDynamicArgs()
    local args = {}

    -- Check if data is available
    local myData = GetMyData()
    if not myData or not next(myData) then
        args.noData = {
            type = "description",
            name = "|cffaaaaaa(No data available yet.)|r",
            order = 1,
        }
        return args
    end

    -- Generate widgets for each data item
    for i, item in ipairs(myData) do
        local colorKey = "itemColor" .. i
        local resetKey = "itemColorReset" .. i

        args[colorKey] = {
            type = "color",
            name = "Item " .. i .. ": " .. item.name,
            order = i * 10,
            width = "double",
            get = function()
                local c = GetItemColor(i)
                return c.r, c.g, c.b
            end,
            set = function(_, r, g, b)
                SetItemColor(i, r, g, b)
            end,
        }

        args[resetKey] = {
            type = "execute",
            name = "X",
            order = i * 10 + 1,
            width = 0.3,
            hidden = function()
                return not HasCustomItemColor(i)
            end,
            func = function()
                ResetItemColor(i)
                AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
            end,
        }
    end

    return args
end

-- Hook to regenerate on each access
local function MyDynamicOptionsTable()
    return {
        type = "group",
        name = "Dynamic Options",
        order = 10,
        args = {
            dynamicGroup = {
                type = "group",
                name = "Items",
                inline = true,
                order = 1,
                args = GenerateDynamicArgs(),  -- Called each time options open
            },
        },
    }
end
```

---

## Best Practices

### 1. Always Use ECM.ScheduleLayoutUpdate(0)

Call this in every `set` function that affects the UI:

```lua
set = function(_, val)
    db.profile.myModule.enabled = val
    ECM.ScheduleLayoutUpdate(0)  -- ✅ Always include
end,
```

### 2. Store nil for Default Values

Keep the config clean by storing `nil` for default/zero values:

```lua
set = function(_, val)
    -- Store nil if value is 0 or default
    db.profile.myModule.height = val > 0 and val or nil
end,
```

### 3. Match Hidden Logic

Reset buttons must match the visibility of their controls:

```lua
-- Control hidden when NOT in free mode
width = {
    hidden = function() return not IsAnchorModeFree(db.profile.myBar) end,
    ...
},

-- Reset must have same condition PLUS value check
widthReset = {
    hidden = function()
        return not IsAnchorModeFree(db.profile.myBar) or not IsValueChanged("myBar.width")
    end,
    ...
},
```

### 4. Use Descriptions Liberally

Help users understand what settings do:

```lua
heightDesc = {
    type = "description",
    name = "Override the default bar height. Set to 0 to use the global default.",
    order = 1,
},
```

### 5. Verify Config Paths

Before writing options code:
1. Open `Defaults.lua`
2. Find the setting's full path
3. Use the exact same structure in Options.lua
4. Test with fresh profile to ensure defaults apply

### 6. Use Consistent Naming

- Description: `<key>Desc`
- Reset button: `<key>Reset`
- Spacer: `spacer1`, `spacer2`, etc.

### 7. Group Related Settings

Use inline groups to organize related settings:

```lua
border = {
    type = "group",
    name = "Border",
    inline = true,
    order = 2,
    args = {
        -- All border settings here
    },
},
```

### 8. Test with Multiple Profiles

After adding new options:
1. Create a new profile
2. Verify defaults apply correctly
3. Change settings and switch profiles
4. Reset individual settings with reset buttons
5. Reset entire profile

---

## Common Mistakes

### ❌ Wrong Config Path
```lua
-- WRONG - Missing .global for global settings
get = function() return db.profile.hideWhenMounted end,

-- CORRECT
get = function() return db.profile.global.hideWhenMounted end,
```

### ❌ Mismatched Reset Button Visibility
```lua
-- WRONG - Reset visible when control is hidden
width = {
    hidden = function() return not IsAnchorModeFree(cfg) end,
},
widthReset = {
    hidden = function() return IsAnchorModeFree(cfg) end,  -- Inverted!
},

-- CORRECT
widthReset = {
    hidden = function()
        return not IsAnchorModeFree(cfg) or not IsValueChanged("width")
    end,
},
```

### ❌ Missing Layout Update
```lua
-- WRONG - Change won't apply until reload
set = function(_, val)
    db.profile.myModule.enabled = val
    -- Missing: ECM.ScheduleLayoutUpdate(0)
end,

-- CORRECT
set = function(_, val)
    db.profile.myModule.enabled = val
    ECM.ScheduleLayoutUpdate(0)
end,
```

### ❌ Wrong Color Picker Return
```lua
-- WRONG - Returning table
get = function()
    return db.profile.myModule.color  -- Returns table
end,

-- CORRECT - Return 4 separate values
get = function()
    local c = db.profile.myModule.color
    return c.r, c.g, c.b, c.a
end,
```

### ❌ Direct UpdateLayout Call
```lua
-- WRONG - Bypasses throttling and proper event handling
set = function(_, val)
    db.profile.buffBars.width = val
    ECM.BuffBars:UpdateLayout()  -- Direct call
end,

-- CORRECT - Use scheduled update
set = function(_, val)
    db.profile.buffBars.width = val
    ECM.ScheduleLayoutUpdate(0)
end,
```

---

## Adding a New Module to Options

1. **Create the generator function:**
```lua
local function MyNewModuleOptionsTable()
    local db = ns.Addon.db
    return {
        type = "group",
        name = "My New Module",
        order = 8,  -- Pick next available order
        args = {
            -- ... settings groups
        },
    }
end
```

2. **Add to GetOptionsTable():**
```lua
local function GetOptionsTable()
    return {
        type = "group",
        name = "Enhanced Cooldown Manager",
        childGroups = "tree",
        args = {
            general = GeneralOptionsTable(),
            powerBar = PowerBarOptionsTable(),
            -- ... other modules
            myNewModule = MyNewModuleOptionsTable(),  -- Add here
            profile = ProfileOptionsTable(),
            about = AboutOptionsTable(),
        },
    }
end
```

3. **Define defaults in Defaults.lua:**
```lua
profile = {
    -- ... other modules
    myNewModule = {
        enabled = true,
        height = 20,
        -- ... other settings
    },
}
```

4. **Test thoroughly:**
- Fresh profile (defaults apply)
- Change settings (persists)
- Reset buttons (restore defaults)
- Profile switching (settings isolated)

---

## Summary Checklist

When adding new options:

- [ ] Settings defined in `Defaults.lua` with correct path
- [ ] Options table generator function created
- [ ] Added to `GetOptionsTable()` args
- [ ] Correct config paths used (global vs module-specific)
- [ ] `ECM.ScheduleLayoutUpdate(0)` called in all `set` functions
- [ ] Reset buttons added where appropriate
- [ ] Reset buttons have matching `hidden` logic
- [ ] Color pickers return/receive 4 separate values
- [ ] Descriptions added for complex settings
- [ ] Order values assigned consistently
- [ ] Tested with fresh profile
- [ ] Tested reset functionality
- [ ] Tested profile switching

---

## Further Reading

- AceConfig-3.0 Documentation: https://www.wowace.com/projects/ace3/pages/ace-config-3-0-options-tables
- LibSharedMedia-3.0: For texture/font/sound media integration
- AceDBOptions-3.0: For profile management UI
