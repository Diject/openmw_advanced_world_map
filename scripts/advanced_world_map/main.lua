local async = require('openmw.async')
local world = require('openmw.world')

local config = require("scripts.advanced_world_map.config.config")

local tableLib = require("scripts.advanced_world_map.utils.table")
local stringLib = require("scripts.advanced_world_map.utils.string")

local log = require("scripts.advanced_world_map.utils.log")

local common = require("scripts.advanced_world_map.common")

local l10n = require("openmw.core").l10n(common.l10nKey)


local function genMapRegionNames()
    local cellNameData = {}
    for _, cell in pairs(world.cells) do
        if not cell.isExterior or not cell.name or cell.name == "" then goto continue end

        local name = stringLib.getBeforeComma(cell.name)

        local cellDt = cellNameData[name]
        if not cellDt then
            cellNameData[name] = {
                name = name, count = 0,
                minX = math.huge, maxX = -math.huge,
                minY = math.huge, maxY = -math.huge,
            }
            cellDt = cellNameData[name]
        end

        cellDt.minX = math.min(cell.gridX, cellDt.minX)
        cellDt.minY = math.min(cell.gridY, cellDt.minY)
        cellDt.maxX = math.max(cell.gridX, cellDt.maxX)
        cellDt.maxY = math.max(cell.gridY, cellDt.maxY)
        cellDt.count = cellDt.count + 1

        ::continue::
    end

    cellNameData = tableLib.values(cellNameData, function (a, b)
        return a.count > b.count
    end)

    local res = {}
    for _, dt in ipairs(cellNameData) do
        if dt.count < 1 then break end
        table.insert(res, {
            name = dt.name,
            count = dt.count,
            posX = (dt.minX + (dt.maxX - dt.minX) / 2) * 8192 + 4096,
            posY = (dt.minY + (dt.maxY - dt.minY) / 2) * 8192 + 4096,
        })
    end

    -- world.players[1]:sendEvent("QGL:updateCityInfo", res)
end

genMapRegionNames()


return {
    engineHandlers = {

    },
    eventHandlers = {
        ["AdvWMap:updateConfigData"] = function (data)
            tableLib.applyChanges(config.data, data)
        end,
    },
}