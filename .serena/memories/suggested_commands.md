# Suggested Commands (Windows / PowerShell)

## Git
- Status: `git status`
- Diff: `git diff`
- Log (recent): `git log -n 20 --oneline --decorate`
- Blame: `git blame -w <file>`
- Search tracked files: `git ls-files | Select-String -Pattern "ViewerHook"`

## PowerShell file/navigation helpers
- List files: `Get-ChildItem` (or `Get-ChildItem -Recurse`)
- Find text: `Select-String -Path .\**\*.lua -Pattern "UpdateLayout"`
- Print working dir: `Get-Location`

## In-game (WoW)
- Reload UI after changes: `/reload`
- Open options: `/ecm` (and `/ecm options`)
- Basic help: `/ecm help`

## Typical manual validation loop
- Make a code change → `/reload`
- Toggle/verify options → ensure no combat taint or blocked actions
- Validate bars anchor/layout relative to Blizzard viewers

Notes:
- No repo-provided lint/test runner configuration was found (no `Makefile`, `package.json`, or `.luacheckrc`).
