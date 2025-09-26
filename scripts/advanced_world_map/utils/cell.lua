local commonData = require("scripts.advanced_world_map.common")

local this = {}


function this.getGridCoordinates(pos)
    local gridX = math.floor(pos.x / 8192)
    local gridY = math.floor(pos.y / 8192)
    return gridX, gridY
end


function this.getCellIdByPos(pos)
    return commonData.exteriorCellIdFormat:format(this.getGridCoordinates(pos))
end



return this