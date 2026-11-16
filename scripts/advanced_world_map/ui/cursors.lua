local ui = require("openmw.ui")
local util = require("openmw.util")
local commonData = require("scripts.advanced_world_map.common")
local uiUtils = require("scripts.advanced_world_map.ui.utils")

local isAvailable = commonData.isCursorAPIavailable()

local this = {}

local cursorMoveTexturePath = "textures/tx_cursormove.dds"
local uiScale = uiUtils.getUIScale()
local size = util.vector2(math.floor(32 * uiScale), math.floor(32 * uiScale))
local hotspot = util.vector2(math.floor(16 * uiScale), math.floor(16 * uiScale))


this.moveHorizontal = isAvailable and ui.cursor{
    path = cursorMoveTexturePath,
    size = size,
    hotspot = hotspot,
} or nil

this.moveVertical = isAvailable and ui.cursor{
    path = cursorMoveTexturePath,
    size = size,
    hotspot = hotspot,
    rotation = math.pi / 2,
} or nil

this.moveDiagonal45 = isAvailable and ui.cursor{
    path = cursorMoveTexturePath,
    size = size,
    hotspot = hotspot,
    rotation = math.pi / 4,
} or nil

this.moveDiagonal135 = isAvailable and ui.cursor{
    path = cursorMoveTexturePath,
    size = size,
    hotspot = hotspot,
    rotation = 3 * math.pi / 4,
} or nil


return this