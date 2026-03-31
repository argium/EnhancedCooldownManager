# Suggested Commands

## Testing
```sh
busted Tests
```
Runs the full Busted test suite from the project root.

## Linting
```sh
luacheck . -q
```
Runs luacheck with quiet output. Config in `.luacheckrc` (std=lua51, excludes libs/ and Tests/).

## Git (Windows/PowerShell)
```powershell
git status
git diff
git log --oneline -10
git add -A; git commit -m "message"
git push   # aliased as 'gp' in user's shell
```

## File Operations (PowerShell)
```powershell
Get-ChildItem -Recurse -Filter "*.lua"
Get-Content <file>
Test-Path <path>
```

## Notes
- The addon runs inside WoW; there is no standalone entry point to execute
- Tests run via `busted` which is a Lua test framework (must be installed on system)
- No formatter configured; style is enforced via code review conventions
