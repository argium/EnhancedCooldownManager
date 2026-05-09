# LibSettingsBuilder Scoped Instructions

Scope: `Libs/LibSettingsBuilder/**`

This library must remain a thin declarative data-model to Blizzard Settings translation layer. Future changes should make the code feel smaller and easier to reason about, not merely move complexity around.

## Architecture Contract

Calls only move down this stack:

```text
Public API
  -> Registry
  -> Schema
  -> Builders
  -> Interop
  -> Foundation
```

Allowed dependencies:

- `Core.lua` bootstraps LibStub and creates `lib._internal` namespaces only.
- `Foundation/` contains pure Lua helpers only. No Blizzard globals, no runtime state.
- `Schema/` contains row kinds, normalization, and validation. It may use `Foundation` only.
- `Registry/` owns `LSB.New`, runtime state, page/section materialization, page handles, refresh, and lifecycle orchestration.
- `Builders/` translates normalized row specs into interop calls. Builders may use `Foundation`, `Schema` data when needed, and `Interop`; they must not call `Registry`.
- `Interop/` is the only layer allowed to call Blizzard/UI APIs or create/mutate frames. It may use `Foundation`, but must not call `Builders`, `Registry`, or schema dispatch.

## Hard Rules

- Keep `lib.*` public-only: `New`, `GetSection`, `GetRootPage`, `GetPage`, and `HasCategory`.
- Do not add public row-constructor methods such as `lib.Checkbox`, `lib.Slider`, or `lib.BorderGroup`.
- Do not call Blizzard globals outside `Interop/`. This includes `Settings`, `SettingsPanel`, `CreateFrame`, `CreateColorFromHexString`, `StaticPopup_*`, `GameTooltip`, `hooksecurefunc`, `MinimalSliderWithSteppersMixin`, scrollbox APIs, and data providers.
- Do not add compatibility aliases for old flat internals such as `internal.applyCollectionFrame` or `internal.createColorSwatch`.
- Prefer deleting, inlining, or simplifying code over adding passthrough wrappers.
- Keep composites declarative: they should build child specs and call builders, not create UI or touch Blizzard APIs.
- Keep migrations and consumer row schemas backward compatible unless a request explicitly says the old behavior is obsolete.

## Validation

For changes under `Libs/LibSettingsBuilder/**`, run:

```sh
busted --run libsettingsbuilder
luacheck . -q
```

The architecture spec must stay green. If it fails, fix the dependency direction instead of weakening the test.

## Documentation

When changing layer boundaries, public row behavior, or load order, update:

- `Libs/LibSettingsBuilder/README.md`
- `Libs/LibSettingsBuilder/docs/API_REFERENCE.md`
- `Libs/LibSettingsBuilder/embed.xml`
- `Tests/TestHelpers.lua` library load order
