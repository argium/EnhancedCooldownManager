# Suggested Commands

## Addon Validation
```sh
busted Tests
luacheck . -q
```

## Library Validation
```sh
busted --run libsettingsbuilder
busted --run libconsole
busted --run libevent
busted --run liblsmsettingswidgets
```

## When They Apply
- Changes to `Modules/`, `UI/`, or any root-level `*.lua` must pass `busted Tests` and `luacheck . -q`.
- Changes under `Libs/<Name>/` must additionally pass that library's suite.

## Useful Git Commands (PowerShell)
```powershell
git status
git diff
git log --oneline -10
git add -A; git commit -m "message"
git push
```

## Useful File Commands (PowerShell)
```powershell
rg "pattern"
rg --files
Get-ChildItem -Recurse -Filter "*.lua"
Get-Content <file>
Test-Path <path>
```

## Notes
- The addon runs inside WoW; there is no standalone runtime entry point.
- Tests run via `busted` and lint via `luacheck`; both must be available on the system.
- No formatter is configured; style is enforced by repo conventions and review.