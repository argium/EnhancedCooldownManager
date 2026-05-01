---
name: pre-release-checklist
description: Run the EnhancedCooldownManager pre-release checklist before publishing or tagging a release. Use when Codex is asked to verify release readiness, prepare a release, review final release risk, or specifically check options schema migration coverage.
---

# Pre-Release Checklist

## Overview

Verify release readiness for EnhancedCooldownManager with emphasis on schema migrations and test coverage. Treat missing verification as a release blocker and report exact gaps.

## Workflow

1. Inspect the pending release changes with `git status --short` and focused diffs.
2. Determine whether the options schema version increased.
3. If the options schema version increased, verify that the schema changes are incorporated into `Migration.lua`.
4. Verify migration test coverage for every schema change.
5. Verify black-box tests cover old saved-variable data migrating to the expected current shape.
6. Ensure `AGENTS.md`, `ARCHITECTURE.md`, and documentation are accurate and consistent with the product code.
7. Ask the user whether `RELEASE_POPUP_VERSION` in `Constants.lua` needs to be updated so that a release prompt is displayed again.
8. If `RELEASE_POPUP_VERSION` needs to be updated, confirm `WHATS_NEW_BODY` in `Locales/en.lua` has been updated in this release.
9. Run the repo validation required by `AGENTS.md` for touched surfaces, or state exactly why validation could not be run.

## Options Schema Checks

When the options schema version increased:

- Confirm `Migration.lua` includes migration logic for the new schema changes.
- Confirm tests cover the migration behavior directly.
- Confirm black-box tests start from representative old saved-variable data and assert the migrated current shape.
- Do not mark the release ready if migration logic or either test class is missing.

## Release Prompt Checks

- Ask the user whether `RELEASE_POPUP_VERSION` in `Constants.lua` needs to be updated so that a release prompt is displayed again.
- If the answer is yes, confirm `WHATS_NEW_BODY` in `Locales/en.lua` has been updated in this release.
- Treat an outdated `WHATS_NEW_BODY` as a release blocker when the release prompt version is updated.

## Reporting

Report release readiness as:

- `Ready`: all applicable checks and validation passed.
- `Blocked`: list each blocker with file paths and missing work.
- `Not verified`: list checks that could not be completed and why.
