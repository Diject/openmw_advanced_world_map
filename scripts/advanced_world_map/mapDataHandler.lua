local core = require("openmw.core")
local storage = require("openmw.storage")
local types = require("openmw.types")
local util = require("openmw.util")

local pDoor = require("scripts.advanced_world_map.helpers.protectedDoor")

local log = require("scripts.advanced_world_map.utils.log")

local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local commonData = require("scripts.advanced_world_map.common")
local cellHelper = require("scripts.advanced_world_map.helpers.cell")

local this = {}

this.version = 9

---@type table<string, advancedWorldMap.dynamicDataHandler.cellData> by cell name
this.cellNameData = nil
---@type table<string, advancedWorldMap.dynamicDataHandler.cellData> by region name
this.regionNameData = nil
---@type table<string, advancedWorldMap.dynamicDataHandler.entranceData[]> by cell id
this.entrances = nil
---@type table<string, string> by cell id
this.cellNameById = nil
---@type table<string, boolean> by cell id
this.validCellsWithoutName = {}
---@type {max : {x : integer, y : integer}, min : {x : integer, y : integer}}
this.grid = nil
---@type {[1] : number, [2] : number, [3] : number, [4] : number}[]
this.worldMapTileRectangles = {}
---@type advancedWorldMap.dynamicDataHandler.transport
this.transport = nil

this.cellCount = 0
this.contentFileCount = 0

local initialized = false


local forbiddenCellPrefixes = { -- lowercase
    ["solstheim"] = true
}


---@class advancedWorldMap.dynamicDataHandler.cellData
---@field posX number
---@field posY number
---@field name string
---@field count integer

---@class advancedWorldMap.dynamicDataHandler.entranceData
---@field pos any position
---@field cId string cell id
---@field isEx boolean is in exterior cell
---@field isLEx boolean is destination in like exterior cell
---@field dCId string destination cell id
---@field dPos any destination position
---@field isDEx boolean is destination cell exterior
---@field isDLEx boolean is destination cell like exterior
---@field name string destination cell name
---@field fName string destination cell full name
---@field pN string? prefix name (for cells with comma in name)
---@field ppN string? second prefix name
---@field dHash string door hash
---@field isIsl boolean? is isolated from other entrances
---@field pHash string? parent entrance hash (for grouped entrances)

---@class advancedWorldMap.dynamicDataHandler.transport
---@field nodes advancedWorldMap.dynamicDataHandler.transport.node[] list of transport nodes
---@field actors table<string, {tp: integer, ns: integer[]}> by npc record id
---@field data table<integer, integer[]> list of node ids by transport type (1 - caravaner, 2 - shipmaster, 3 - guild guide, 4 - gondolier)

---@class advancedWorldMap.dynamicDataHandler.transport.node
---@field tp integer type (1 - caravaner, 2 - shipmaster, 3 - guild guide, 4 - gondolier)
---@field p Vector2 position
---@field ls integer[] list of node ids that have this node in their list of destinations
---@field ars string[]? list of actor record ids that are on this node


function this.getClusterBoundingBox(cluster)
    local fpos = cluster[1].pos
    local minX, maxX = fpos.x, fpos.x
    local minY, maxY = fpos.y, fpos.y
    for _, m in pairs(cluster) do
        local pos = m.pos
        if pos.x < minX then minX = pos.x end
        if pos.x > maxX then maxX = pos.x end
        if pos.y < minY then minY = pos.y end
        if pos.y > maxY then maxY = pos.y end
    end
    return {x = util.vector2(minX, minY), y = util.vector2(maxX, maxY), center = util.vector2((minX + maxX) / 2, (minY + maxY) / 2)}
end


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


local function worldCoverWithRectanglesFast(occupied)
    local res = {}

    local xCoords = {}
    for x in pairs(occupied) do
        table.insert(xCoords, x)
    end
    table.sort(xCoords)

    for _, x in ipairs(xCoords) do
        local col = occupied[x]
        if col then
            local yCoords = {}
            for y in pairs(col) do
                table.insert(yCoords, y)
            end
            table.sort(yCoords)

            local i = 1
            while i <= #yCoords do
                local y1 = yCoords[i]
                local y2 = y1

                while i < #yCoords and yCoords[i + 1] == y2 + 1 do
                    i = i + 1
                    y2 = yCoords[i]
                end

                local x2 = x
                local canExpandX = true
                while canExpandX do
                    local nextX = x2 + 1
                    local nextCol = occupied[nextX]
                    if nextCol then

                        for y = y1, y2 do
                            if not nextCol[y] then
                                canExpandX = false
                                break
                            end
                        end

                        if canExpandX then
                            x2 = nextX
                        end
                    else
                        canExpandX = false
                    end
                end

                table.insert(res, {x, y1, x2, y2})

                for xi = x, x2 do
                    local c = occupied[xi]
                    if c then
                        for y = y1, y2 do
                            c[y] = nil
                        end
                        if not next(c) then
                            occupied[xi] = nil
                        end
                    end
                end

                i = i + 1
            end
        end
    end

    return res
end


---@param entrances table<string, advancedWorldMap.dynamicDataHandler.entranceData[]>
local function buildTransportData(entrances)
    local world = require("openmw.world")

    local transportNpcs = {}
    local nodes = {}
    local exitNodes = {}
    local transportClass = {
        ["caravaner"] = 1,
        ["shipmaster"] = 2,
        ["t_mw_riverstriderservice"] = 2,
        ["guild guide"] = 3,
        ["gondolier"] = 4,
    }
    local transport = {nodes = nodes, actors = transportNpcs, data = {}}
    for _, id in pairs(transportClass) do
        transport.data[id] = {}
    end
    transport.data[-1] = {}

    local function getNodeId(pos, tp)
        local unknownTypeNode
        local unknownTypeNodeId
        local unknownTypeNodeDist = math.huge
        local node
        local nodeId
        local dist = math.huge
        for i, nodeDt in pairs(nodes) do
            local d = commonData.distance2D(nodeDt.p, pos)

            if nodeDt.tp == tp or (tp == -1 and nodeDt.tp ~= -1) then
                if d < dist then
                    dist = d
                    node = nodeDt
                    nodeId = i
                end
            end

            if nodeDt.tp == -1 and tp ~= -1 then
                if d < unknownTypeNodeDist then
                    unknownTypeNodeDist = d
                    unknownTypeNode = nodeDt
                    unknownTypeNodeId = i
                end
            end
        end

        if node and dist < 3072 then
            return nodeId, node
        end

        if unknownTypeNode and unknownTypeNodeDist < 3072 then
            unknownTypeNode.tp = tp
            return unknownTypeNodeId, unknownTypeNode
        end

        local ind = #nodes + 1
        nodes[ind] = {tp = tp, p = pos, ls = {}}
        return ind, nodes[ind]
    end

    for _, rec in pairs(types.NPC.records) do
        if not rec.travelDestinations then
            goto continue
        end

        local data = {tp = transportClass[rec.class or ""] or -1, ns = {}}

        for _, destDt in pairs(rec.travelDestinations) do
            if not destDt.cellId then goto continue end
            if destDt.cellId:find(commonData.exteriorCellLabel) then
                local pos = destDt.position
                local nodeId = getNodeId(pos, data.tp)

                data.ns[nodeId] = true
            else
                local cachedExitNode = exitNodes[destDt.cellId]
                if cachedExitNode then
                    data.ns[cachedExitNode] = true
                else
                    local exits = cellHelper.findExitPoss(destDt.cellId, entrances)
                    if not exits or not exits[1] then goto continue end

                    local exit = exits[1]
                    local nodeId = getNodeId(exit, data.tp)
                    data.ns[nodeId] = true

                    exitNodes[destDt.cellId] = nodeId
                end
            end

            ::continue::
        end

        if next(data.ns) then
            data.ns = tableLib.keys(data.ns)
            transportNpcs[rec.id] = data
        end

        ::continue::
    end

    for _, cell in pairs(world.cells) do
        if not cell.id then goto continue end

        local actors = cell:getAll(types.NPC)
        for _, actor in pairs(actors) do
            local transporterData = transportNpcs[actor.recordId]
            if not transporterData then goto continue end

            local actorNodeId
            if cell.isExterior then
                actorNodeId = getNodeId(actor.position, transporterData.tp)
            else
                local cachedExitNode = exitNodes[cell.id]
                if cachedExitNode then
                    actorNodeId = cachedExitNode
                else
                    local exits = cellHelper.findExitPoss(cell.id, entrances)
                    if not exits or not exits[1] then goto continue end

                    local exit = exits[1]
                    local nodeId = getNodeId(exit, transporterData.tp)
                    actorNodeId = nodeId

                    exitNodes[cell.id] = nodeId
                end
            end

            if actorNodeId then
                local actorNode = nodes[actorNodeId]
                if actorNode then
                    actorNode.ars = actorNode.ars or {}
                    table.insert(actorNode.ars, actor.recordId)

                    for _, nodeId in pairs(transporterData.ns) do
                        if nodeId ~= actorNodeId then
                            local nDt = nodes[nodeId]
                            if not nDt then goto continue end

                            if nDt.tp == -1 then
                                nDt.tp = actorNode.tp
                            end

                            actorNode.ls[nodeId] = true
                        end

                        ::continue::
                    end

                end
            end

            ::continue::
        end

        ::continue::
    end

    for i, nodeDt in pairs(nodes) do
        nodeDt.ls = tableLib.keys(nodeDt.ls)
        table.insert(transport.data[nodeDt.tp], i)
    end

    return transport
end


local function buildData(params)
    local world = require("openmw.world")

    local isPrecizeOccupied = params.isPrecizeOccupied

    local function getRegionName(id)
        if not id then return "" end
        if not core.regions or not core.regions.records then return stringLib.capitalizeFirst(id) end

        local region = core.regions.records[id]
        if not region then return stringLib.capitalizeFirst(id) end

        return region.name or ""
    end

    this.cellNameById = {}
    this.validCellsWithoutName = {}

    local minGridX = math.huge
    local minGridY = math.huge
    local maxGridX = -math.huge
    local maxGridY = -math.huge

    local cellNameData = {}
    local regionNameData = {}
    local entrances = {}
    local occupied = {}
    local exCellSecondPrefixes = {}
    this.cellCount = #world.cells
    for _, cell in pairs(world.cells) do
        if not cell.isExterior or not cell.id then goto continue end

        if cell.gridX > 1000 or cell.gridX < -1000 or cell.gridY > 1000 or cell.gridY < -1000 then
            goto continue
        end

        minGridX = math.min(minGridX, cell.gridX)
        maxGridX = math.max(maxGridX, cell.gridX)
        minGridY = math.min(minGridY, cell.gridY)
        maxGridY = math.max(maxGridY, cell.gridY)

        if isPrecizeOccupied and core.land then
            local posX = cell.gridX * 8192
            local posY = cell.gridY * 8192
            local aboveWater = 0
            for i = 1024, 8192, 2048 do
                for j = 1024, 8192, 2048 do
                    if core.land.getHeightAt(util.vector3(posX + i, posY + j, 0), cell) > 0 then
                        aboveWater = aboveWater + 1
                    end
                end
            end
            if aboveWater > 8 then
                occupied[cell.gridX] = occupied[cell.gridX] or {}
                occupied[cell.gridX][cell.gridY] = true
            end
        else
            occupied[cell.gridX] = occupied[cell.gridX] or {}
            occupied[cell.gridX][cell.gridY] = true
        end

        if not cell.name or cell.name == "" then goto continue end

        local name, pName = stringLib.getBeforeAfterComma(cell.name)
        if cell.isExterior and pName then
            local n, p = stringLib.getBeforeAfterComma(cell.displayName or cell.name)
            if p then
                exCellSecondPrefixes[cell.id] = p
            end
        end

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


    local function buildRectMapFast()
        this.worldMapTileRectangles = worldCoverWithRectanglesFast(occupied)
    end

    if not pcall(buildRectMapFast) then
        log("Error building world map tile rectangles")
        this.worldMapTileRectangles = {}
    end

    this.grid = {min = {x = minGridX, y = minGridY}, max = {x = maxGridX, y = maxGridY}}

    local function getCellName(cell)
        local name = cell.displayName or cell.name
        if cell.isExterior then
            if not name or name == "" then
                name = getRegionName(cell.region)
            end
        end
        return name
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

        local hash = math.floor(posY / 6144)
        for i = -1, 1 do
            local h = hash + i
            cellNameLines[h] = cellNameLines[h] or {}
            table.insert(cellNameLines[h], cellDt)
        end

        ::continue::
    end

    ---@type table<string, advancedWorldMap.dynamicDataHandler.entranceData[]>
    local entrancesWithCellName = {}
    local populationMap = {}
    -- local exNames = {}

    for _, cell in pairs(world.cells) do
        if not cell.id then goto continue end

        local cellName = getCellName(cell)
        this.cellNameById[cell.id] = cellName
        if not cellName then
            this.validCellsWithoutName[cell.id] = true
        end

        local doors = cell:getAll(types.Door)
        for _, door in pairs(doors) do
            if not types.Door.isTeleport(door) then goto continue end

            local dest = pDoor.destCell(door)
            local destPos = pDoor.destPosition(door)

            if not dest or not destPos then goto continue end

            local exTypeCellName
            local name = getCellName(dest)
            local prefixName
            local fullName = name
            if name:find(",") or name:find("，") then
                if not dest.isExterior then
                    local nm, cellNameMark = stringLib.getAfterBeforeComma(name)
                    if cellNames[cellNameMark] then
                        exTypeCellName = cellNameMark
                        name = nm
                    end

                    if cell.isExterior then
                        prefixName = cellNameMark

                        local cellIdMark = stringLib.getBeforeComma(dest.id)
                        if forbiddenCellPrefixes[cellIdMark] then
                            fullName = name
                        end
                    end
                else
                    name = stringLib.getAfterComma(name)
                end
            end

            local doorHash = commonData.doorHash(door, dest.id or "")

            entrances[cell.id] = entrances[cell.id] or {}
            ---@type advancedWorldMap.dynamicDataHandler.entranceData
            local data = {
                pos = door.position,
                cId = cell.id,
                isEx = cell.isExterior,
                dCId = dest.id or "",
                dPos = destPos,
                isDEx = dest.isExterior,
                name = name,
                fName = fullName,
                pN = prefixName,
                dHash = doorHash,
                isDLEx = dest.isExterior or dest:hasTag("QuasiExterior"),
                isLEx = cell.isExterior or cell:hasTag("QuasiExterior"),
            }
            entrances[cell.id][doorHash] = data

            if cell.isExterior then
                local x = math.floor(data.pos.x / 1024)
                local y = math.floor(data.pos.y / 1024)
                local id = x * 100000 + y
                populationMap[id] = populationMap[id] or {x = x, y = y, m = {}}
                table.insert(populationMap[id].m, data)
            end

            if exTypeCellName and cell.isExterior then
                entrancesWithCellName[exTypeCellName] = entrancesWithCellName[exTypeCellName] or {}
                table.insert(entrancesWithCellName[exTypeCellName], data)

                if prefixName then
                    local sPrefixes = {}
                    for x = cell.gridX - 1, cell.gridX + 1 do
                        for y = cell.gridY - 1, cell.gridY + 1 do
                            local pp = exCellSecondPrefixes[commonData.exteriorCellIdFormat:format(x, y)]
                            if pp and not sPrefixes[pp] then
                                sPrefixes[pp] = x == cell.gridX and y == cell.gridY
                            end
                        end
                    end
                    for sPrefix, isCurrentCell in pairs(sPrefixes) do
                        if isCurrentCell then
                            data.ppN = sPrefix
                        end
                        if data.name:sub(1, #sPrefix) == sPrefix then
                            data.ppN = sPrefix
                            data.name = stringLib.trimStart(data.name:sub(#sPrefix + 1))
                        end
                    end
                end
            end

            ::continue::
        end

        ::continue::
    end

    for _, list in pairs(entrancesWithCellName) do
        if #list <= 2 then
            for _, dt in pairs(list) do
                dt.name = dt.fName
            end
        end
    end


    local mergeDist = 768 * 768
    local nameGroups = {}
    for _, lst in pairs(entrances) do
        for _, dt in pairs(lst) do
            nameGroups[dt.name] = nameGroups[dt.name] or {}
            table.insert(nameGroups[dt.name], dt)
        end
    end

    for _, entries in pairs(nameGroups) do
        local used = {}
        local entryCount = #entries
        for i = 1, entryCount do
            if not used[i] then
                used[i] = true

                local entry = entries[i]
                local cluster = { entry }
                local expanded = true
                for k = 1, 5 do
                    expanded = false
                    for j = 1, entryCount do
                        if not used[j] then
                            local ej = entries[j]
                            if ej.isEx and entry.isEx or ej.cId == entry.cId then
                                for _, cm in pairs(cluster) do
                                    local dx = cm.pos.x - ej.pos.x
                                    local dy = cm.pos.y - ej.pos.y
                                    if dx * dx + dy * dy <= mergeDist then
                                        used[j] = true
                                        table.insert(cluster, ej)
                                        expanded = true
                                        break
                                    end
                                end
                            end
                        end
                    end

                    if not expanded then break end
                end

                local cx, cy = 0, 0
                for _, e in pairs(cluster) do
                    cx = cx + e.pos.x
                    cy = cy + e.pos.y
                end
                local clusterSize = #cluster
                cx = cx / clusterSize
                cy = cy / clusterSize

                local bestEntry = cluster[1]
                local bestDist = math.huge
                for _, e in pairs(cluster) do
                    local dx = e.pos.x - cx
                    local dy = e.pos.y - cy
                    local dsq = dx * dx + dy * dy
                    if dsq < bestDist then
                        bestDist = dsq
                        bestEntry = e
                    end
                end

                local repDt = bestEntry

                for _, e in pairs(cluster) do
                    if e ~= repDt then
                        e.pHash = repDt.dHash
                    end
                end
            end
        end
    end

    for _, data in pairs(populationMap) do
        local x = data.x
        local y = data.y
        for _, dt in pairs(data.m) do
            local maxDist = dt.fName == dt.name and 2048 or 6144
            local steps = math.ceil(maxDist / 1024)

            local isolated = true
            local function check()
                for i = x - steps, x + steps do
                    for j = y - steps, y + steps do
                        local popData = populationMap[i * 100000 + j]
                        if popData then
                            for _, d in pairs(popData.m) do
                                if (d.name ~= dt.name and d.name:sub(1, #dt.name) ~= dt.name) and
                                        (d.pN ~= nil) == (dt.pN ~= nil) and
                                        commonData.distance2D(d.pos, dt.pos) < maxDist then
                                    isolated = false
                                    return
                                end
                            end
                        end
                    end
                end
            end
            check()

            dt.isIsl = isolated or nil
        end
    end


    local function processLines(lines, xPosDiff, heightDiff)
        for _, lineElems in pairs(lines) do

            table.sort(lineElems, function (a, b)
                return a.posX < b.posX
            end)

            for j = 2, #lineElems do
                local el1 = lineElems[j - 1]
                local el2 = lineElems[j]
                local xDiff = el2.posX - el1.posX
                local yDiff = math.abs(el2.posY - el1.posY)
                if xDiff < xPosDiff and yDiff < heightDiff then
                    local heightDiffHalf = (heightDiff - yDiff) * 0.5
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

    this.transport = buildTransportData(entrances)
end


function this.globalBuildData(playerRef, options)
    buildData(options)
    playerRef:sendEvent("AdvWMap:updateMapData", {
        cellNameData = this.cellNameData,
        regionNameData = this.regionNameData,
        entrances = this.entrances,
        cellNameById = this.cellNameById,
        validCellsWithoutName = this.validCellsWithoutName,
        grid = this.grid,
        worldMapTileRectangles = this.worldMapTileRectangles,
        transport = this.transport,
        cellCount = this.cellCount,
        options = options,
        plId = playerRef.id,
    })
    initialized = true
end


function this.globalInit(playerRef, options)
    if not playerRef then return end
    local cells = require("openmw.world").cells
    playerRef:sendEvent("AdvWMap:initMapData", {cellCount = #cells, options = options})
end


function this.playerInit(playerRef, cellCount, options)
    options = options or {}
    local stor = storage.playerSection(commonData.mapDataStorageName)

    local shouldRebuild = options.force or stor:get("version") ~= this.version or stor:get("cellCount") ~= cellCount or
        stor:get("contentFileCount") ~= #core.contentFiles.list

    if shouldRebuild then
        local dataSettingStorage = storage.playerSection(commonData.configDataSectionName)
        options.isPrecizeOccupied = dataSettingStorage:get("data.initializer") == commonData.dataInitializerTypes[6]

        if not commonData.isSaveBloatFixed() and require("scripts.advanced_world_map.config.config").data.data.safeInit then
            types.Player.sendMenuEvent(playerRef, "AdvWMap:startDataRebuilding", {plId = playerRef.id, options = options})
        else
            core.sendGlobalEvent("AdvWMap:rebuildMapData", {plId = playerRef.id, options = options})
        end
        return false
    else
        local data = stor:asTable()

        this.cellNameData = data.cellNameData or {}
        this.regionNameData = data.regionNameData or {}
        this.entrances = data.entrances or {}
        this.cellNameById = data.cellNameById or {}
        this.validCellsWithoutName = data.validCellsWithoutName or {}
        this.grid = data.grid or {min = {x = 0, y = 0}, max = {x = 0, y = 0}}
        this.worldMapTileRectangles = data.worldMapTileRectangles or {}
        this.transport = data.transport or {}
        this.cellCount = data.cellCount or 0
        this.contentFileCount = data.contentFileCount or 0

        core.sendGlobalEvent("AdvWMap:updateMapData", {
            cellNameData = this.cellNameData,
            regionNameData = this.regionNameData,
            entrances = this.entrances,
            cellNameById = this.cellNameById,
            grid = this.grid,
            worldMapTileRectangles = this.worldMapTileRectangles,
            transport = this.transport,
            validCellsWithoutName = this.validCellsWithoutName,
        })

        if options then
            playerRef:sendEvent("AdvWMap:processMapDataOptions", options)
        end

        initialized = true

        return true
    end
end



function this.updateData(playerRef, data)
    this.cellNameData = data.cellNameData or {}
    this.regionNameData = data.regionNameData or {}
    this.entrances = data.entrances or {}
    this.cellNameById = data.cellNameById or {}
    this.validCellsWithoutName = data.validCellsWithoutName or {}
    this.grid = data.grid or {min = {x = 0, y = 0}, max = {x = 0, y = 0}}
    this.worldMapTileRectangles = data.worldMapTileRectangles or {}
    this.transport = data.transport or {}
    this.cellCount = data.cellCount or 0
    this.contentFileCount = data.contentFileCount or 0

    local stor = storage.playerSection(commonData.mapDataStorageName)
    stor:set("cellNameData", this.cellNameData)
    stor:set("regionNameData", this.regionNameData)
    stor:set("entrances", this.entrances)
    stor:set("cellNameById", this.cellNameById)
    stor:set("validCellsWithoutName", this.validCellsWithoutName)
    stor:set("grid", this.grid)
    stor:set("worldMapTileRectangles", this.worldMapTileRectangles)
    stor:set("transport", this.transport)
    stor:set("cellCount", this.cellCount)
    stor:set("contentFileCount", #core.contentFiles.list)
    stor:set("version", this.version)
    stor:set("apiVersion", core.API_REVISION)

    log("Map data updated and saved to storage")
    if not commonData.isSaveBloatFixed() and require("scripts.advanced_world_map.config.config").data.data.safeInit then
        types.Player.sendMenuEvent(playerRef, "AdvWMap:finishDataRebuilding", {plId = data.plId, options = data.options})
    else
        core.sendGlobalEvent("AdvWMap:processMapDataOptions", {plId = data.plId, options = data.options})
    end

    initialized = true
end


function this.loadMapData(data)
    this.cellNameData = data.cellNameData or {}
    this.regionNameData = data.regionNameData or {}
    this.entrances = data.entrances or {}
    this.cellNameById = data.cellNameById or {}
    this.validCellsWithoutName = data.validCellsWithoutName or {}
    this.grid = data.grid or {min = {x = 0, y = 0}, max = {x = 0, y = 0}}
    this.worldMapTileRectangles = data.worldMapTileRectangles or {}
    this.transport = data.transport or {}

    initialized = true
end


function this.isInitialized()
    return initialized
end


return this