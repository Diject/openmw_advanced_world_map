local ui = require("openmw.ui")
local util = require("openmw.util")
local commonData = require("scripts.advanced_world_map.common")

local isAvailable = commonData.isCursorAPIavailable()

local this = {}

local cursorMoveTexturePath = "textures/tx_cursormove.dds"


this.moveHorizontal = isAvailable and ui.cursor{
    path = cursorMoveTexturePath,
    size = util.vector2(32, 32),
    hotspot = util.vector2(16, 16),
} or nil

this.moveVertical = isAvailable and ui.cursor{
    path = cursorMoveTexturePath,
    size = util.vector2(32, 32),
    hotspot = util.vector2(16, 16),
    rotation = math.pi / 2,
} or nil

this.moveDiagonal45 = isAvailable and ui.cursor{
    path = cursorMoveTexturePath,
    size = util.vector2(32, 32),
    hotspot = util.vector2(16, 16),
    rotation = math.pi / 4,
} or nil


return this