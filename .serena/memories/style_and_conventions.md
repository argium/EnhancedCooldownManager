# Code Style and Conventions

## Copyright Header (MANDATORY on all .lua files)
```lua
-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
```

## Naming
- Constants: UPPER_SNAKE_CASE (stored in ECM_Constants.lua, accessed via `ECM.Constants`)
- Functions/methods: PascalCase (e.g., `GetGlobalConfig`, `OnEnable`)
- Private methods/fields: prefixed with underscore (e.g., `_configKey`, `_updateBar`)
- Local variables: camelCase
- Module names: PascalCase (e.g., `PowerBar`, `BuffBars`)

## Type Annotations
- Use LuaCATS `@class`, `@field`, `@param`, `@return` annotations
- Place `@class` annotations at top of file after copyright header
- Group related `@field` annotations within each class
- Add descriptions: getters start with "Gets ...", setters with "Sets ..."

## Architecture Rules
- **ALL constants** must be in ECM_Constants.lua
- Modules using ModuleMixin must use `self:GetGlobalConfig()` and `self:GetModuleConfig()` -- never `mod.db` or `mod.db.profile` directly
- NEVER create intermediate tables for profile/config
- NEVER listen to `OnUpdate` event
- No forward declarations
- Prefer loose coupling: events, hooks, callbacks for inter-module communication
- Use assertions liberally to catch error states

## Testing
- New features/regression fixes in `/Bars`, `/Modules`, `/UI`, and `ECM.lua` MUST include test cases
- Tests use Busted framework with WoW API stubs in Tests/stubs/
- Test files named `*_spec.lua`

## Code Review Standards
- No unused variables
- No unnecessary assignments, guards, functions, boilerplate
- Comments for complex sections (but not redundant comments restating function names)
- No code duplication
- Minimal complexity; simplicity is paramount
- Remove dead code, trivial wrappers, dead type checking
