---
name: pre-release-checklist
description: Run the EnhancedCooldownManager pre-release checklist before dispatching a release workflow. Use when Codex is asked to verify release readiness, prepare a release, review final release risk, or specifically check options schema migration coverage.
---

# Pre-Release Checklist

## Overview

Verify release readiness for EnhancedCooldownManager with emphasis on schema migrations, test coverage, release preconditions, and manual workflow steps. Treat missing verification as a release blocker and report exact gaps.

## Workflow

1. Inspect the pending release changes with `git status --short` and focused diffs.
2. Determine whether the options schema version increased.
3. If the options schema version increased, verify that the schema changes are incorporated into `Migration.lua`.
4. Verify migration test coverage for every schema change.
5. Verify black-box tests cover old saved-variable data migrating to the expected current shape.
6. Ensure `AGENTS.md`, `ARCHITECTURE.md`, and documentation are accurate and consistent with the product code.
7. Ask the user whether `RELEASE_POPUP_VERSION` in `Constants.lua` needs to be updated so that a release prompt is displayed again.
8. If `RELEASE_POPUP_VERSION` needs to be updated, confirm `WHATS_NEW_BODY` in `Locales/en.lua` has been updated in this release.
9. Verify the release preconditions below.
10. Run the repo validation required by `AGENTS.md` for touched surfaces, or state exactly why validation could not be run.

## Release Preconditions

- Confirm `EnhancedCooldownManager.toc` has the final `## Version:` value and that it starts with `v`.
- Treat versions containing `-` as prereleases. Stable versions must be released from `main`; prereleases may be released from any pushed branch.
- Confirm the TOC version change is committed before dispatch; unrelated local edits do not block the helper.
- Confirm release notes are prepared for `scripts/start-release.ps1 -Message` or `-MessagePath`.
- Confirm `gh auth status` succeeds when the helper script will be used.
- Confirm no conflicting remote tag or GitHub Release already exists for the TOC version; a remote tag that already points at the dispatch commit is allowed only for a retry.
- Treat an existing remote tag that points at another commit, existing GitHub Release, missing release notes, failed validation, or wrong release branch as a release blocker.

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

## Manual Release Steps

1. Run this checklist and resolve all blockers.
2. Update `RELEASE_POPUP_VERSION` and `WHATS_NEW_BODY` when a release prompt should be shown.
3. Dispatch the release with `scripts/start-release.ps1 -Message "..."`; use `-MessagePath` for multiline release notes.
4. Monitor the `release.yml` workflow until validation completes.
5. Approve the `release` environment after validation succeeds.
6. Verify the workflow created the GitHub tag, GitHub Release, and release artifacts.

## Reporting

Report release readiness as:

- `Ready`: all applicable checks and validation passed.
- `Blocked`: list each blocker with file paths and missing work.
- `Not verified`: list checks that could not be completed and why.
