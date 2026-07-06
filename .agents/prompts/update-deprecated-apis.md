Use this prompt to refresh the deprecated Blizzard API denylist (`docs/BlizzardDeprecatedApis.md`) when a new Retail client build ships, or when the current denylist is stale.

The denylist is generated, not hand-maintained. `scripts/update-deprecated-apis.ps1` reads every `Blizzard_Deprecated*` folder from the `Gethe/wow-ui-source` mirror at a given tag and rewrites the doc. Fix the script if the output is wrong; never hand-edit the generated doc.

```text
Regenerate the deprecated Blizzard API denylist for client version `<VERSION>` (for example 12.0.7).

Steps:
1. From the repo root, run the generator:
   pwsh -File scripts/update-deprecated-apis.ps1 -Tag <VERSION> -Verbose
   It discovers every Blizzard_Deprecated* addon folder in Gethe/wow-ui-source at that tag, extracts the
   top-level deprecated symbols (functions, namespaced/mixin functions, constants, aliases, mixin tables),
   and overwrites docs/BlizzardDeprecatedApis.md.

2. Review `git diff -- docs/BlizzardDeprecatedApis.md`. Confirm added/removed folders and symbols look right,
   and spot-check two or three sections against the source tree at
   https://github.com/Gethe/wow-ui-source/tree/<VERSION>/Interface/AddOns.

3. Update the version references that name the denylist build so they match `<VERSION>`:
   - `AGENTS.md` "Deprecated Blizzard APIs" section (the "<old> denylist" wording).
   - `.serena/memories/repo/secret-values-and-deprecated-apis.md` heading.
   - `.serena/memories/style_and_conventions.md` "for <old>." line.

4. If a newly deprecated global is one the addon calls directly, replace it with the modern C_* API; do not
   add deprecated APIs. If luacheck now reports an undefined global that the addon legitimately uses, update
   `.luacheckrc` read_globals rather than the code.

5. Validate:
   - Re-run the generator with `-WhatIf` and confirm it reports no further change.
   - If any Lua or `.luacheckrc` changed, run `luacheck . -q` and `busted Tests`.

6. Commit the regenerated doc and the version-reference updates together.

Notes:
- The script needs network access to api.github.com (one tree listing) and raw.githubusercontent.com (file
  contents). Set `GITHUB_TOKEN` to avoid API rate limits on the tree call.
- Extraction is scope-aware: it ignores function bodies, table literals, and block comments, so only the
  top-level shim definitions are captured. Mixin methods are intentionally omitted in favor of the mixin
  table name. If a section is grouped or filtered incorrectly, fix scripts/update-deprecated-apis.ps1 and
  regenerate, do not patch the Markdown by hand.
```

## Example Invocation

```text
Use `.agents/prompts/update-deprecated-apis.md` to update the deprecated API denylist for 12.0.7.
```
