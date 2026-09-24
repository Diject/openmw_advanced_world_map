local util = require("openmw.util")

local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local dateLib = require("scripts.advanced_world_map.utils.date")
local cellLib = require("scripts.advanced_world_map.utils.cell")

local eventSys = require("scripts.advanced_world_map.eventSys")
local config = require("scripts.advanced_world_map.config.config")

local commonData = require("scripts.advanced_world_map.common")
local scriptLib = require("scripts.advanced_world_map.utils.script")
local dialogueLib = require("scripts.advanced_world_map.utils.dialogue")

local mapDataHandler = require("scripts.advanced_world_map.mapDataHandler")
local localStorage = require("scripts.advanced_world_map.storage.localStorage")

local this = {}

local discoveryBlockCount = 4
local discoveryBlockSize = math.ceil(8192 / discoveryBlockCount)
local discoveryBlockSizeHalf = math.ceil(discoveryBlockSize / 2)


---@type table<string, number> by cell id or cell name
this.visited = {}
---@type table<string, integer|table<integer, integer>|boolean> by cell id or cell name
this.discovered = {}
---@type table<string, any>
this.pending = {}

this.blockDiscovery = false


function this.addVisitedCell(cell)
    local timeStamp = dateLib.getGlobalTimestamp()
    if not this.visited[cell.id] then
        local res = {cell.id}

        this.visited[cell.id] = timeStamp
        local cellName = cell.displayName or cell.name or ""
        if cellName ~= "" then
            if cell.isExterior then
                this.visited[cellName] = timeStamp
                table.insert(res, cellName)
                local name = stringLib.getBeforeComma(cellName)
                this.visited[name] = timeStamp
                table.insert(res, name)
            elseif cellName:find(",", 1, true) or cellName:find("，", 1, true) then
                local name = stringLib.getBeforeComma(cellName)
                this.visited[name] = timeStamp
                table.insert(res, name)
            end
        end

        return res
    else
        this.visited[cell.id] = timeStamp
    end
end


function this.updateVisited(cell)
    if this.visited[cell.id] then
        this.visited[cell.id] = dateLib.getGlobalTimestamp()
    end
end


function this.addDiscoveredCell(cell, addNearbyExteriors)
    if this.blockDiscovery then return end

    local newDiscovered = {}

    if cell.isExterior and addNearbyExteriors then
        for i = -1, 1 do
            for j = -1, 1 do
                local cId = commonData.exteriorCellIdFormat:format(cell.gridX + i, cell.gridY + j)
                if not this.discovered[cId] then
                    this.discovered[cId] = 0
                    newDiscovered[cId] = true
                end
            end
        end
    end

    if not this.discovered[cell.id] then
        if cell.isExterior then
            this.discovered[cell.id] = 0
        else
            this.discovered[cell.id] = {}
        end
        newDiscovered[cell.id] = true

        local cellName = cell.displayName or cell.name
        if cellName:find(",", 1, true) or cellName:find("，", 1, true) then
            local name = stringLib.getBeforeComma(cellName)
            this.discovered[name] = 0
            newDiscovered[name] = true
        end
    end

    if next(newDiscovered) then
        eventSys.triggerEvent(eventSys.EVENT.onDiscover, {discoveredMap = newDiscovered})
        return tableLib.keys(newDiscovered)
    end
end


function this.addPending(names)
    tableLib.copy(names, this.pending)
end


local function discoverNames(names)
    local newDiscovered = {}

    for _, name in pairs(names) do
        if not this.discovered[name] then
            this.discovered[name] = 0
            newDiscovered[name] = true
        end
    end

    if next(newDiscovered) then
        eventSys.triggerEvent(eventSys.EVENT.onDiscover, {discoveredMap = newDiscovered})
        return tableLib.keys(newDiscovered)
    end
end


function this.addFromDialogueScript(diaId, infoId)
    local diaInfo = dialogueLib.getDialogueTopicInfo(diaId, infoId)
    if not diaInfo or not diaInfo.resultScript then return end

    local places = scriptLib.getShowMapPlaces(diaInfo.resultScript)
    if not places then return end

    if not mapDataHandler.isInitialized() then
        tableLib.copy(places, this.pending)
        return
    end

    local names = {}
    for place, _ in pairs(places) do
        local name = mapDataHandler.worldNameById[place]
        if name then
            table.insert(names, name)
        end
    end

    return discoverNames(names)
end


function this.updatePending()
    if not mapDataHandler.isInitialized() or not next(this.pending) then return end

    local names = {}
    for id, _ in pairs(this.pending) do
        local name = mapDataHandler.worldNameById[id]
        if name then
            table.insert(names, name)
        end

        this.pending[id] = nil
    end

    return discoverNames(names)
end


function this.getDiscoveryMask(x, y)
    local rowX = math.floor((x % 8192) / discoveryBlockSize)
    local rowY = math.floor((y % 8192) / discoveryBlockSize)
    local bitMaskX = 2 ^ (rowX + rowY * discoveryBlockCount)
    return bitMaskX
end


function this.getDiscoveryInteriorMaskId(x, y)
    return math.floor(100 + x / 8192) + math.floor(100 + y / 8192) * 200
end


function this.getSetDiscoveryInfoForPosition(cellId, isExterior, pos, updateData)
    local changed

    local function processExPos(x, y)
        local cId = cellLib.getCellIdByPos(util.vector2(x, y))
        local dt = changed and changed[cId] or this.discovered[cId]
        if not dt then
            dt = 0
        elseif type(dt) ~= "number" then
            return
        elseif dt == 0xffff then
            return
        end
        local old = dt

        dt = util.bitOr(dt, this.getDiscoveryMask(x, y))

        if updateData then
            this.discovered[cId] = dt

            if dt ~= old then
                changed = changed or {}
                changed[cId] = dt
            end
        else
            changed = changed or {}
            changed[cId] = dt
        end
    end

    local function processInPos(x, y)
        local data = this.discovered[cellId]
        if not data then
            data = {}
            if updateData then
                this.discovered[cellId] = data
            end
        elseif type(data) ~= "table" then
            return
        end
        local id = this.getDiscoveryInteriorMaskId(x, y)
        local dt = changed and changed[id] or data[id]
        if dt and dt == 0xffff then return end

        local old = dt
        dt = dt or 0

        dt = util.bitOr(dt, this.getDiscoveryMask(x, y))
        if updateData then
            data[id] = dt

            if dt ~= old then
                changed = changed or {}
                changed[id] = dt
            end
        else
            changed = changed or {}
            changed[id] = dt
        end
    end

    local radius = config.data.main.discoveryRadius
    local radiusMul = radius < discoveryBlockSize and 1 or math.floor((radius + discoveryBlockSizeHalf) / discoveryBlockSize)

    local blockSizePadding = isExterior and discoveryBlockSize or math.ceil(discoveryBlockSize / 2)
    blockSizePadding = blockSizePadding * radiusMul
    local blockSize = isExterior and discoveryBlockSize or blockSizePadding * 2
    for x = pos.x - blockSizePadding, pos.x + blockSizePadding, blockSize do
        for y = pos.y - blockSizePadding, pos.y + blockSizePadding, blockSize do
            if isExterior then
                processExPos(x, y)
            else
                processInPos(x, y)
            end
        end
    end

    return changed
end


function this.discoverPosition(cell, pos)
    local cellId = cell.id

    local isExterior = cell.isExterior

    local changed = this.getSetDiscoveryInfoForPosition(cellId, isExterior, pos, true)
    return changed
end


function this.getDiscoveredMaskData(cellId)
    return this.discovered[cellId]
end


function this.isPositionDiscovered(cellId, pos)
    local data = this.discovered[cellId]
    if data then
        if type(data) == "number" then
            local msk = this.getDiscoveryMask(pos.x, pos.y)
            return util.bitAnd(msk, data) ~= 0
        elseif type(data) == "table" then
            local d = data[this.getDiscoveryInteriorMaskId(pos.x, pos.y)]
            local msk = this.getDiscoveryMask(pos.x, pos.y)
            return d and util.bitAnd(msk, d) ~= 0 or false
        else
            return true
        end
    end
    return false
end


function this.init()
    if not localStorage.isPlayerStorageReady() then return end

    if not localStorage.data[commonData.visitedLocsFieldId] then
        localStorage.data[commonData.visitedLocsFieldId] = {}
    end
    this.visited = localStorage.data[commonData.visitedLocsFieldId]

    if not localStorage.data[commonData.discoveredLocsFieldId] then
        localStorage.data[commonData.discoveredLocsFieldId] = {}
    end
    this.discovered = localStorage.data[commonData.discoveredLocsFieldId]

    if not localStorage.data[commonData.pendingDiscoveredLocsFieldId] then
        localStorage.data[commonData.pendingDiscoveredLocsFieldId] = {}
    end
    this.pending = localStorage.data[commonData.pendingDiscoveredLocsFieldId]
end


---@return boolean
function this.isDiscovered(name)
    return this.discovered[name] and true or false
end


---@param id string
---@return number?
function this.isVisited(id)
    return this.visited[id]
end



return this