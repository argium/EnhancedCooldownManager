# Task Completion Checklist

When completing a task, perform these steps:

1. **Verify constants**: Any new constants must be in `ECM_Constants.lua`
2. **Copyright header**: All new/modified .lua files must have the standard header
3. **Run tests**: `busted Tests`
4. **Run linter**: `luacheck . -q`
5. **Code review** (for anything beyond a small targeted fix):
   - Check for unused variables
   - Check for unnecessary assignments, guards, boilerplate
   - Verify no code duplication
   - Ensure complex sections have comments
   - Verify test coverage for changes in Modules/, UI/, ECM.lua
   - Ensure loose coupling between components
   - Remove dead code and trivial wrappers
6. **Config access**: Modules using ModuleMixin use `self:GetGlobalConfig()` / `self:GetModuleConfig()` only
7. **No OnUpdate**: Never use the OnUpdate event
8. **No forward declarations**
