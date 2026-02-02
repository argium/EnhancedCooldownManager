**NOTE: **The code is undergoing a signficant refactor. Try to align with the new design.

## Design

**All constants** are to be stored in Constants.lua.

The profile is split into GLOBAL and a SECTION specific to the module (typically matching the file name, in camel case).  See [Defaults.lua](Defaults.lua)

The intention is to use mixins as a kind of class hierarchy:
 ECMFrame -> BarFrame -> PowerBar|ResourceBar|RuneBar
 ECMFrame -> BuffBars

[ECMFrame](Mixins\ECMFrame.lua) owns:
- The "inner" Blizzard Frame
- Layout including positioning, anchor, border, background
- Refresh throttling
- Hiding

ECMFrame should work with _any_ frame the addon needs to position or hide.

[BarFrame](Mixins\BarFrame.lua) owns:
- StatusBar (values, color, texture)
- Appearance
- Text
- Ticks

BarFrame should work with any bar-style frame the addon is resposnible for drawing and updating.

[Bars\*](Bars\*.lua) owns:
- Event registeration and handlers
- Concrete implmementations for GetStatusBarValue, ticks, etc.

These responsibilities can change over time so update this document if so however responsibilities should not cross mixins by reaching into the internals of another. Always use public interfaces. Internal fields are prefixed by an underscore.

MANDATORY: Modules that derive from ECMFrame, must use the config accessors and never `ECM.db` or `ECM.db.profile` directly.
- `self:GetGlobalConfig()` for the `global` config block
- `self:GetConfigSection()` for the module's specific block

MANDATORY: Modules should call methods in the immediate parent's mixin, if present. For example, `PowerBar:Refresh` must call `BarFrame.Refresh(self)` and never `ECMFrame.Refresh(self)`

[Modules\Layout.lua](Modules\Layout.lua) owns
- Registering events that affect every ECMFrame such as hiding when the player mounts.
- Tells ECMFrames when to show/hide themselves, or when to refresh in response to global events.

The goal is to replace ViewerHook and then remove it.

## Rewrite/Refactor

The following files have been mostly rewritten, but not everything is implemented:
- [Mixins\BarFrame.lua](Mixins\BarFrame.lua)
- [Mixins\ECMFrame.lua](Mixins\ECMFrame.lua)

The following files are partially rewritten:
- [Bars\BuffBars.lua](Bars\BuffBars.lua)
- [Bars\ResourceBar.lua](Bars\ResourceBar.lua)
- [Bars\RuneBar.lua](Bars\RuneBar.lua)

The following file will probably be removed:
- [Mixins\PositionStrategy.lua](Mixins\PositionStrategy.lua)
- [Modules\ViewerHook.lua](Modules\ViewerHook.lua) (replace with Layout.lua)

Store architectural details, status, and design choices and trade off decisions in [REFACTOR.md](docs\REFACTOR.md) so that you can reload your progress later. It is okay to make suggestions for design and architecture and layout, if it is a significant improvement or if the current design deviates wildly from what a reasonable developer in the WoW addon space would do.
