local core = require("openmw.core")
local storage = require("openmw.storage")
local types = require("openmw.types")

local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local commonData = require("scripts.advanced_world_map.common")

local this = {}

this.version = 1

---@type table<string, advancedWorldMap.dynamicDataHandler.cellData> by cell name
this.cellNameData = nil
---@type table<string, advancedWorldMap.dynamicDataHandler.cellData> by region name
this.regionNameData = nil
---@type table<string, advancedWorldMap.dynamicDataHandler.entranceData[]> by cell id
this.entrances = nil
---@type table<string, string> by cell id
this.cellNameById = nil


---@class advancedWorldMap.dynamicDataHandler.cellData
---@field posX number
---@field posY number
---@field name string
---@field count integer

---@class advancedWorldMap.dynamicDataHandler.entranceData
---@field pos any
---@field destCellId string
---@field destPos any
---@field isDestEx boolean
---@field name string
---@field fullName string
---@field doorHash string

local function isContentFile(name)
    name = name:lower()

    local suffixes = {"esm", "esp", "omwaddon"}
    for _, suf in ipairs(suffixes) do
        if stringLib.isEndsWith(name, suf) then
            return true
        end
    end
    return false
end



local function buildData()
    local world = require("openmw.world")

    local function getRegionName(id)
        if not id then return "" end
        if not core.regions then return stringLib.capitalizeFirst(id) end

        local region = core.regions[id]
        if not region then return stringLib.capitalizeFirst(id) end

        return region.name or ""
    end

    this.cellNameById = {}

    local cellNameData = {}
    local regionNameData = {}
    local entrances = {}
    for _, cell in pairs(world.cells) do
        if not cell.isExterior then goto continue end
        if not cell.name or cell.name == "" then goto continue end

        local name = stringLib.getBeforeComma(cell.name)

        local cellDt = cellNameData[name]
        if not cellDt then
            cellDt = {
                name = stringLib.getBeforeComma(cell.displayName or cell.name), count = 0,
                minX = math.huge, maxX = -math.huge,
                minY = math.huge, maxY = -math.huge,
            }
            cellNameData[name] = cellDt
        end

        cellDt.minX = math.min(cell.gridX, cellDt.minX)
        cellDt.minY = math.min(cell.gridY, cellDt.minY)
        cellDt.maxX = math.max(cell.gridX, cellDt.maxX)
        cellDt.maxY = math.max(cell.gridY, cellDt.maxY)
        cellDt.count = cellDt.count + 1

        if cell.region then
            local regDt = regionNameData[cell.region]
            if not regDt then
                regDt = {
                    name = getRegionName(cell.region), count = 0,
                    minX = math.huge, maxX = -math.huge,
                    minY = math.huge, maxY = -math.huge,
                }
                regionNameData[cell.region] = regDt
            end

            regDt.minX = math.min(cell.gridX, regDt.minX)
            regDt.minY = math.min(cell.gridY, regDt.minY)
            regDt.maxX = math.max(cell.gridX, regDt.maxX)
            regDt.maxY = math.max(cell.gridY, regDt.maxY)
            regDt.count = regDt.count + 1
        end

        ::continue::
    end

    local function getCellName(cell)
        local name = cell.displayName or cell.name
        if cell.isExterior then
            if not name or name == "" then
                name = getRegionName(cell.region)
            end
        end
        return name
    end

    for _, cell in pairs(world.cells) do

        this.cellNameById[cell.id] = getCellName(cell)

        local doors = cell:getAll(types.Door)
        for _, door in pairs(doors) do
            if not types.Door.isTeleport(door) then goto continue end

            local dest = types.Door.destCell(door)
            local destPos = types.Door.destPosition(door)

            local name = getCellName(dest)
            if name:find(",") then
                if cell.isExterior then
                    local cellNameMark = stringLib.getBeforeComma(name)
                    if cellNameData[cellNameMark] then
                        name = stringLib.getAfterComma(name)
                    end
                else
                    name = stringLib.getAfterComma(name)
                end
            end

            local doorHash = commonData.doorHash(door, dest.id)

            entrances[cell.id] = entrances[cell.id] or {}
            entrances[cell.id][doorHash] = {
                pos = door.position,
                destCellId = dest.id,
                destPos = destPos,
                isDestEx = dest.isExterior,
                name = name,
                fullName = getCellName(dest),
                doorHash = doorHash,
            }

            ::continue::
        end

        ::continue::
    end


    local cellNameLines = {}
    local cellNames = {}
    for _, dt in pairs(cellNameData) do
        if dt.count < 1 then goto continue end

        local posX = (dt.minX + (dt.maxX - dt.minX) / 2) * 8192 + 4096
        local posY = (dt.minY + (dt.maxY - dt.minY) / 2) * 8192 + 4096

        local cellDt = {
            name = dt.name,
            count = dt.count,
            posX = posX,
            posY = posY,
        }
        cellNames[dt.name] = cellDt

        local hash = math.floor(posY / 4096)
        for i = -1, 1 do
            local h = hash + i
            cellNameLines[h] = cellNameLines[h] or {}
            table.insert(cellNameLines[h], cellDt)
        end

        ::continue::
    end


    local function processLines(lines, xPosDiff, heightDiff)
        local heightDiffHalf = heightDiff / 2
        for _, lineElems in pairs(lines) do

            table.sort(lineElems, function (a, b)
                return a.posX < b.posX
            end)

            for j = 2, #lineElems do
                local el1 = lineElems[j - 1]
                local el2 = lineElems[j]
                if el2.posX - el1.posX < xPosDiff and math.abs(el2.posY - el1.posY) < heightDiff then
                    if el1.posY > el2.posY then
                        el1.posY = el1.posY + heightDiffHalf
                        el2.posY = el2.posY - heightDiffHalf
                    else
                        el1.posY = el1.posY - heightDiffHalf
                        el2.posY = el2.posY + heightDiffHalf
                    end
                end
            end
        end
    end

    processLines(cellNameLines, 8192 * 6, 4096)

    this.cellNameData = cellNames


    local regNameLines = {}
    local regNames = {}
    for _, dt in pairs(regionNameData) do
        if dt.count < 1 then goto continue end

        local posX = (dt.minX + (dt.maxX - dt.minX) / 2) * 8192 + 4096
        local posY = (dt.minY + (dt.maxY - dt.minY) / 2) * 8192 + 4096

        local cellDt = {
            name = dt.name,
            count = dt.count,
            posX = posX,
            posY = posY,
        }
        regNames[dt.name] = cellDt

        local hash = math.floor(posY / 8192)
        for i = -1, 1 do
            local h = hash + i
            regNameLines[h] = regNameLines[h] or {}
            table.insert(regNameLines[h], cellDt)
        end

        ::continue::
    end

    processLines(regNameLines, 8192 * 12, 8192)

    this.regionNameData = regNames


    for cellId, list in pairs(entrances) do
        entrances[cellId] = tableLib.values(list)
    end
    this.entrances = entrances

end



function this.init()
    local stor = storage.globalSection(commonData.globalDataStorageName)

    local shouldRebuild = (stor:get("version") ~= this.version) or (stor:get("gameFiles") == nil)
shouldRebuild = true
    local gameFiles

    if not shouldRebuild then
        gameFiles = {}

        for _, name in ipairs(core.contentFiles.list) do
            if isContentFile(name) then
                table.insert(gameFiles, name)
            end
        end

        local storageGameFiles = stor:get("gameFiles") or {}
        if #storageGameFiles ~= #gameFiles then
            shouldRebuild = true
        else
            for i, name in ipairs(storageGameFiles) do
                if gameFiles[i] ~= name then
                    shouldRebuild = true
                    break
                end
            end
        end
    end

    if shouldRebuild then
        buildData()
        stor:set("cellNameData", this.cellNameData)
        stor:set("regionNameData", this.regionNameData)
        stor:set("entrances", this.entrances)
        stor:set("cellDirections", this.cellDirections)
        stor:set("cellNameById", this.cellNameById)
    else
        this.cellNameData = stor:get("cellNameData") or {}
        this.regionNameData = stor:get("regionNameData") or {}
        this.entrances = stor:get("entrances") or {}
        this.cellDirections = stor:get("cellDirections") or {}
        this.cellNameById = stor:get("cellNameById") or {}
    end

    require("openmw.world").players[1]:sendEvent("AdvWMap:updateMapData", {
        cellNameData = this.cellNameData,
        regionNameData = this.regionNameData,
        entrances = this.entrances,
        cellDirections = this.cellDirections,
        cellNameById = this.cellNameById
    })
end



function this.load(data)
    this.cellNameData = data.cellNameData or {}
    this.regionNameData = data.regionNameData or {}
    this.entrances = data.entrances or {}
    this.cellDirections = data.cellDirections or {}
    this.cellNameById = data.cellNameById or {}
end


return this