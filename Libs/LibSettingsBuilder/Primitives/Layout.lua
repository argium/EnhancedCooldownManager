-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local copyMixin = internal.copyMixin
local Deprecated = lib.LSBDeprecated

function lib:_createRootCategory(name)
    local category, layout = Settings.RegisterVerticalLayoutCategory(name)
    self._rootCategory = category
    self._rootCategoryName = name
    self._layouts[category] = layout
    self._currentSubcategory = nil
    return category
end

function lib:_createSubcategory(name, parentCategory)
    local parent = parentCategory or self._rootCategory
    local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(parent, name)
    self._currentSubcategory = self:_storeCategory(name, subcategory, layout)
    return subcategory
end

function lib:_createCanvasSubcategory(frame, name, parentCategory)
    local parent = parentCategory or self._rootCategory
    local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)
    return self:_storeCategory(name, subcategory, layout)
end

--- Creates a canvas subcategory with a CanvasLayout engine attached.
--- Returns a layout object with AddHeader, AddDescription, AddSlider,
--- AddColorSwatch, AddButton, AddScrollList methods that position
--- controls to match Blizzard's vertical-layout settings pages.
---@param name string  Subcategory display name.
---@param parentCategory? table  Parent category (defaults to root).
---@return table layout  CanvasLayout instance (layout.frame for the raw frame).
function lib:CreateCanvasLayout(name, parentCategory)
    local frame = CreateFrame("Frame", nil)
    self:_createCanvasSubcategory(frame, name, parentCategory)
    local metrics = copyMixin({}, internal.CanvasLayoutDefaults)
    return setmetatable({
        frame = frame,
        yPos = 0,
        elements = {},
        _metrics = metrics,
    }, { __index = internal.CanvasLayout })
end

Deprecated.CreateCanvasLayout = function(...)
    return lib.CreateCanvasLayout(...)
end
