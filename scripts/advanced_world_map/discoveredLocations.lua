local stringLib = require("scripts.advanced_world_map.utils.string")

local commonData = require("scripts.advanced_world_map.common")

local localStorage = require("scripts.advanced_world_map.storage.localStorage")

local this = {}


---@type table<string, boolean> by cell id or cell name
this.visited = nil

this.blockDiscovery = false


function this.addCell(cell)
    if this.blockDiscovery then return end

    if cell.isExterior then
        for i = -1, 1 do
            for j = -1, 1 do
                this.visited[commonData.exteriorCellIdFormat:format(cell.gridX + i, cell.gridY + j)] = true
            end
        end
    end
    this.visited[cell.id] = true
    this.visited[stringLib.getBeforeComma(cell.name)] = true
    this.visited[stringLib.getAfterComma(cell.name)] = true
end


function this.init()
    if not localStorage.isPlayerStorageReady() then return end

    if not localStorage.data[commonData.discoveredLocsFieldId] then
        localStorage.data[commonData.discoveredLocsFieldId] = {}
    end
    this.visited = localStorage.data[commonData.discoveredLocsFieldId]
end


---@return boolean
function this.isDiscovered(name)
    return this.visited and this.visited[name] and true or false
end



return this