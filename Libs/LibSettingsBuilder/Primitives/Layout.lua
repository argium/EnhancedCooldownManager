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

function lib._installPrimitiveLayout(SB, env)
    local storeCategory = env.storeCategory

    function SB.CreateRootCategory(name)
        local category, layout = Settings.RegisterVerticalLayoutCategory(name)
        SB._rootCategory = category
        SB._rootCategoryName = name
        SB._layouts[category] = layout
        SB._currentSubcategory = nil
        return category
    end

    function SB.CreateSubcategory(name, parentCategory)
        local parent = parentCategory or SB._rootCategory
        local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(parent, name)
        SB._currentSubcategory = storeCategory(name, subcategory, layout)
        return subcategory
    end

    function SB.CreateCanvasSubcategory(frame, name, parentCategory)
        local parent = parentCategory or SB._rootCategory
        local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)
        return storeCategory(name, subcategory, layout)
    end

    --- Creates a canvas subcategory with a CanvasLayout engine attached.
    --- Returns a layout object with AddHeader, AddDescription, AddSlider,
    --- AddColorSwatch, AddButton, AddScrollList methods that position
    --- controls to match Blizzard's vertical-layout settings pages.
    ---@param name string  Subcategory display name.
    ---@param parentCategory? table  Parent category (defaults to root).
    ---@return table layout  CanvasLayout instance (layout.frame for the raw frame).
    function SB.CreateCanvasLayout(name, parentCategory)
        local frame = CreateFrame("Frame", nil)
        SB.CreateCanvasSubcategory(frame, name, parentCategory)
        local metrics = copyMixin({}, lib.CanvasLayoutDefaults)
        return setmetatable({
            frame = frame,
            yPos = 0,
            elements = {},
            _metrics = metrics,
        }, { __index = lib.CanvasLayout })
    end

    return SB
end
