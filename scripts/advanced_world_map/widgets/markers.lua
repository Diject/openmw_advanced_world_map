local core = require("openmw.core")
local util = require("openmw.util")
local ui = require("openmw.ui")
local types = require("openmw.types")
local playerRef = require("openmw.self")

local pDoor = require("scripts.advanced_world_map.helpers.protectedDoor")

local eventSys = require("scripts.advanced_world_map.eventSys")

local uiUtils = require("scripts.advanced_world_map.ui.utils")
local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local cellLib = require("scripts.advanced_world_map.utils.cell")
local dateLib = require("scripts.advanced_world_map.utils.date")

local commonData = require("scripts.advanced_world_map.common")
local mapDataHandler = require("scripts.advanced_world_map.mapDataHandler")
local mapTextureHandler = require("scripts.advanced_world_map.mapTextureHandler")
local discoveredLocs = require("scripts.advanced_world_map.discoveredLocations")
local disabledDoors = require("scripts.advanced_world_map.disabledDoors")

local config = require("scripts.advanced_world_map.config.configLib")

local tooltip = require("scripts.advanced_world_map.ui.tooltip")
local interval = require("scripts.advanced_world_map.ui.interval")

local l10n = core.l10n(commonData.l10nKey)

local mapMarkerTexture = ui.texture{ path = commonData.mapMarkerPath }
local mapMarker45Texture = ui.texture{ path = commonData.mapMarkerForExPath }


local this = {}


---@type advancedWorldMap.ui.menu.map?
this.activeMenuMeta = nil

---@type table<string, table<string, advancedWorldMap.ui.mapElementMeta>>
this.markersByName = {}

---@type table<string, table<string, advancedWorldMap.ui.mapElementMeta>>
this.entranceMarkersByDestCellId = {}

---@type table<string, table<string, advancedWorldMap.ui.mapElementMeta>>
this.markersByDoorHash = {}

---@type table<string, advancedWorldMap.ui.mapElementMeta>
this.markerById = {}



---@param newDiscovered string[]
function this.updateDiscovered(newDiscovered)
    if not this.markersByName or not this.entranceMarkersByDestCellId then return end

    local function updateVisibility(handler)
        local userData = handler:getUserData()
        if not userData then return end
        userData.discovered = true
        if not userData.disabled and not userData.filtered then
            handler:setVisibility(true)
        else
            handler:updateParams{visible = true} ---@diagnostic disable-line: missing-fields
        end
    end

    for _, name in pairs(newDiscovered or {}) do
        for _, handler in pairs(this.entranceMarkersByDestCellId[name] or {}) do
            updateVisibility(handler)
            local userData = handler:getUserData()
            if userData and userData.cellId then
                if discoveredLocs.isVisited(userData.cellId) then
                    handler:setColor(userData.useWorldColor and config.data.ui.worldDefaultLightColor or
                        config.data.ui.defaultLightColor)
                elseif discoveredLocs.isDiscovered(userData.cellId) then
                    handler:setColor(userData.useWorldColor and config.data.ui.worldDefaultColor or
                        config.data.ui.markerDefaultColor)
                end
            end
        end

        for _, handler in pairs(this.markersByName[name] or {}) do
            local userData = handler:getUserData()
            if userData and userData.type == commonData.cityRegionMarkerType then
                updateVisibility(handler)
                handler:setColor(config.data.ui.worldDefaultLightColor)
                if config.data.ui.worldMarkerShadow then
                    handler._params.shadowColor = config.data.ui.worldMarkerShadowColor
                    handler._elemLayout.props.textShadowColor = config.data.ui.worldMarkerShadowColor
                end
            end
        end
    end
end


---@param marker advancedWorldMap.ui.mapElementMeta
local function updateDoorMarkerVisibility(marker, visible)
    local userData = marker:getUserData()
    if not userData then return end

    if userData.type == commonData.doorDescrMarkerType then
        if not userData.filtered then
            marker:setVisibility(visible)
        else
            marker:updateParams{visible = visible} ---@diagnostic disable-line: missing-fields
        end
        userData.disabled = not visible
    elseif userData.type == commonData.doorMarkerType then
        marker:setAlpha(visible and (config.data.legend.alpha.entrance * 0.01) or (config.data.legend.alpha.entrance * 0.01 / 4))
    end
end


function this.updateDoorMarkerVisibility(doorRef)
    local destCell = pDoor.destCell(doorRef)
    if not destCell then return end

    local doorHash = commonData.doorHash(doorRef, destCell.id)
    local visible = not disabledDoors.contains(doorRef)

    local markers = this.markersByDoorHash[doorHash]
    if not markers then return end

    for _, marker in pairs(markers) do
        updateDoorMarkerVisibility(marker, visible)
    end
end


---@return advancedWorldMap.ui.mapElementMeta?
function this.getMarkerById(id)
    return this.markerById[id]
end


---@param cellId string?
---@param x number
---@param y number
---@param label string?
---@return string
function this.getMarkerId(cellId, x, y, label)
    return string.format("%s_%s_%d_%d", label, cellId, x, y)
end


local function createWorldMarkers(widget)
    if eventSys.triggerEvent(eventSys.EVENT.onCellMarkersCreate, {mapWidget = widget}) then
        return
    end

    for _, dt in pairs(mapDataHandler.cellNameData or {}) do
        local id = string.format("%s%d_%d", dt.name, dt.posX, dt.posY)

        local isCellDiscovered = not config.data.legend.onlyDiscovered or discoveredLocs.isDiscovered(dt.name) or
            types.Player.journal and types.Player.journal(playerRef).topics[dt.name] and true or false

        this.markersByName[dt.name] = this.markersByName[dt.name] or {}

        local isVisited = discoveredLocs.isVisited(dt.name)
        local textMarkerHandler = widget:createTextMarker{
            id = id,
            layerId = widget.LAYER.name,
            text = dt.name,
            anchor = util.vector2(0.5, 0.5),
            pos = util.vector2(dt.posX, dt.posY),
            color = isVisited and config.data.ui.worldDefaultLightColor or config.data.ui.worldDefaultColor,
            textShadow = config.data.ui.worldMarkerShadow and true or nil,
            shadowColor = config.data.ui.worldMarkerShadow and
                (isVisited and config.data.ui.worldMarkerShadowColor or config.data.ui.worldMarkerShadowLightColor) or nil,
            fontSize = util.round(config.data.legend.worldMarkerSize + math.min(8, dt.count) * 2),
            scaleFunc = widget.SCALE_FUNCTION.linear,
            alpha = config.data.legend.alpha.city * 0.01,
            useCache = true,
            showWhenZoomedOut = true,
            visible = isCellDiscovered,
            userData = {
                type = commonData.cityRegionMarkerType,
                searchText = stringLib.utf8_lower(dt.name),
                allowSearchFilter = true,
            },
        }
        if textMarkerHandler then
            this.markersByName[dt.name][id] = textMarkerHandler
            this.markerById[id] = textMarkerHandler
        end
    end


    for _, info in pairs(mapDataHandler.regionNameData or {}) do
        local fontSize = math.floor(config.data.legend.worldMarkerSize * 1.2 + math.min(8, info.count) * 3)
        widget:createTextMarker{
            layerId = widget.LAYER.region,
            text = info.name,
            anchor = util.vector2(0.5, 0.5),
            pos = util.vector2(info.posX, info.posY),
            color = discoveredLocs.isVisited(info.name) and config.data.ui.worldDefaultLightColor or config.data.ui.worldDefaultColor,
            fontSize = fontSize,
            scaleFunc = widget.SCALE_FUNCTION.linear,
            alpha = config.data.legend.alpha.region * 0.01,
            showWhenZoomedOut = true,
            useCache = true,
            searchText = stringLib.utf8_lower(info.name),
            searchLabel = l10n("Region")..": "..info.name,
            userData = {
                type = commonData.cityRegionMarkerType,
            }
        }
    end

    widget:update()
end


local function getClusterBoundingBox(cluster)
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

---@return {c: table, cnt: number, bb: table}[]
local function gridClustering(grid)
    local clusters = {}

    local checked = {}
    local function addNearby(key, arr)
        local dt = grid[key]
        if not dt then return end

        for x = dt.x - 1, dt.x + 1 do
            for y = dt.y - 1, dt.y + 1 do
                local nKey = string.format("%d_%d", x, y)
                if checked[nKey] then goto continue end

                local nDt = grid[nKey]
                checked[nKey] = true
                if nDt then
                    tableLib.addValues(nDt.m, arr)
                    addNearby(nKey, arr)
                end

                ::continue::
            end
        end
    end


    for key, arr in pairs(grid) do
        if checked[key] then goto continue end

        local cluster = {}
        addNearby(key, cluster)

        table.insert(clusters, {
            c = cluster,
            cnt = #cluster,
            bb = getClusterBoundingBox(cluster)
        })

        ::continue::
    end

    return clusters
end


---@param destCellId string
local function getWorldMarkerColor(cellId, destCellId, pos)
    local hasTexture = mapTextureHandler.isWorldLocalMapTextureExists(cellLib.getGridCoordinates(pos))
    if config.data.tileset.onlyDiscovered and not discoveredLocs.isDiscovered(cellId) then
        hasTexture = false
    end
    local color
    local shadowColor
    if discoveredLocs.isDiscovered(destCellId) then
        if discoveredLocs.isVisited(destCellId) then
            color = hasTexture and config.data.ui.defaultLightColor or config.data.ui.worldDefaultLightColor
            shadowColor = hasTexture and config.data.ui.markerBackgroundColor or config.data.ui.markerBackgroundAltColor
        else
            color = hasTexture and config.data.ui.markerDefaultColor or config.data.ui.worldDefaultColor
            shadowColor = hasTexture and config.data.ui.markerBackgroundColor or config.data.ui.markerBackgroundAltColor
        end
    else
        color = hasTexture and config.data.ui.defaultDarkColor or config.data.ui.worldDefaultDarkColor
        shadowColor = hasTexture and config.data.ui.markerBackgroundColor or config.data.ui.markerBackgroundAltColor
    end

    return color, shadowColor, hasTexture
end


local entranceAnchors = {
    util.vector2(0.5, -0.5),
    util.vector2(0, 0.5),
    util.vector2(1, 0.5),
    util.vector2(0.5, 1.5),
    util.vector2(0.25, 2),
    util.vector2(0.75, 2),
    util.vector2(0.25, -1),
    util.vector2(0.75, -1),

    util.vector2(0.5, -1.5),
    util.vector2(0, 1.5),
    util.vector2(1, 1.5),
    util.vector2(0.5, 2.5),
    util.vector2(-0.25, 2),
    util.vector2(1.25, 2),
    util.vector2(-0.25, -1),
    util.vector2(1.25, -1),

    util.vector2(0.5, -2.5),
    util.vector2(0, 2.5),
    util.vector2(1, 2.5),
    util.vector2(0.5, 3.5),
    util.vector2(-0.1, 3),
    util.vector2(1.1, 3),
    util.vector2(-0.1, -2),
    util.vector2(1.1, -2),
}


---@param widget advancedWorldMap.ui.mapWidgetMeta
local function createMarkers(widget, cellId, allowedCells)
    if eventSys.triggerEvent(eventSys.EVENT.onCellMarkersCreate, {mapWidget = widget, cellId = cellId}) then
        return
    end
    local entrances = mapDataHandler.entrances or {}

    local isExterior = cellId == nil
    local widgetZoom = widget.zoom
    local doGroup = isExterior and widgetZoom * 32 / widget.mapInfo.pixelsPerCell <= (config.data.legend.zoomToGroup / uiUtils.getUIScale())

    local targetZoom = allowedCells and widgetZoom or 30 / widget.eScale
    local fontInWorldCoords = widget.SCALE_FUNCTION.marker(config.data.legend.markerSize, targetZoom) * 8192 /
        (widget.mapInfo.pixelsPerCell * targetZoom * widget.eScale)
    local charHeight = fontInWorldCoords
    local lineHeight = cellId and charHeight / 10 or charHeight / 4
    local mergeDist = 768 * 768
    local freeMarkerMul = 1.75

    local entrancesData = {}

    if allowedCells then
        for cId, _ in pairs(allowedCells) do
            local cellEntrances = entrances[cId]
            if cellEntrances then
                entrancesData[cId] = cellEntrances
            end
        end
    elseif cellId == nil then
        for cId, list in pairs(entrances) do
            if cId:find(commonData.exteriorCellLabel) then
                entrancesData[cId] = list
            end
        end
    else
        local entranceData = entrances[cellId]
        if not entranceData then return end

        entrancesData[cellId] = entranceData
    end

    local nameGroups = {}
    for _, lst in pairs(entrancesData) do
        for _, dt in pairs(lst) do
            nameGroups[dt.name] = nameGroups[dt.name] or {}
            table.insert(nameGroups[dt.name], dt)
        end
    end

    ---@type table<any, {dt: any, entries: any[], textMarker: advancedWorldMap.ui.mapElementMeta?}>
    local dataForTextMarkers = {}
    local allData = {}

    for _, entries in pairs(nameGroups) do
        local used = {}
        local entryCount = #entries
        for i = 1, entryCount do
            if not used[i] then
                used[i] = true

                local cluster = { entries[i] }
                local expanded = true
                for k = 1, 10 do
                    expanded = false
                    for j = 1, entryCount do
                        if not used[j] then
                            local ej = entries[j]
                            for _, cm in ipairs(cluster) do
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

                    if not expanded then break end
                end

                local cx, cy = 0, 0
                for _, e in ipairs(cluster) do
                    cx = cx + e.pos.x
                    cy = cy + e.pos.y
                end
                local clusterSize = #cluster
                cx = cx / clusterSize
                cy = cy / clusterSize

                local bestEntry = cluster[1]
                local bestDist = math.huge
                for _, e in ipairs(cluster) do
                    local dx = e.pos.x - cx
                    local dy = e.pos.y - cy
                    local dsq = dx * dx + dy * dy
                    if dsq < bestDist then
                        bestDist = dsq
                        bestEntry = e
                    end
                end

                local repDt = bestEntry

                local dt = {
                    dt = repDt,
                    entries = cluster,
                    textMarker = nil,
                }
                table.insert(allData, dt)

                for _, e in ipairs(cluster) do
                    dataForTextMarkers[e] = dt
                end
            end
        end
    end

    ---@type table<integer, {dt: any, mInfo: any, line: integer}[]>
    local entranceByLine = {}
    local maxLine, minLine

    local populationMap = {}
    ---@type table<advancedWorldMap.ui.mapElementMeta, boolean>
    local freeMarkers = {}

    for _, mInfo in ipairs(allData) do
        local dt = mInfo.dt
        local line = math.floor(dt.pos.y / lineHeight)
        entranceByLine[line] = entranceByLine[line] or {}
        table.insert(entranceByLine[line], { line = line, dt = dt, mInfo = mInfo })
        maxLine = math.max(maxLine or line, line)
        minLine = math.min(minLine or line, line)
    end

    for _, line in pairs(entranceByLine) do
        table.sort(line, function (a, b)
            return a.dt.pos.x < b.dt.pos.x
        end)
    end

    local groupClusters
    local markerByData = {}

    if minLine and maxLine then

        ---@type {[1] : number, [2] : number}[][]
        local textLines = {}
        local ungrouped = {}

        local eps = doGroup and 5.5 * fontInWorldCoords * config.data.ui.textHeightMul or 6144
        if isExterior then
            for _, lst in pairs(entrancesData) do
                for _, dt in pairs(lst) do
                    local x, y = math.floor(dt.pos.x / eps), math.floor(dt.pos.y / eps)
                    local posId = string.format("%d_%d", x, y)
                    populationMap[posId] = populationMap[posId] or {x = x, y = y, m = {}}
                    table.insert(populationMap[posId].m, dt)
                end
            end

            if doGroup then
                groupClusters = gridClustering(populationMap)
                for _, clusterDt in pairs(groupClusters) do
                    if clusterDt.cnt < 3 then
                        for _, dt in pairs(clusterDt.c) do
                            ungrouped[dt] = true
                        end
                    end
                end
            end
        end

        for cId, lst in pairs(entrancesData) do
            for _, dt in pairs(lst) do
                local size = charHeight * 0.25
                local imgS = dt.pos.x - size
                local imgE = dt.pos.x + size
                local line0Id = math.floor((dt.pos.y - size) / lineHeight)
                local line1Id = math.ceil((dt.pos.y + size) / lineHeight)
                for i = line0Id, line1Id do
                    textLines[i] = textLines[i] or {}
                    table.insert(textLines[i], {imgS, imgE})
                end

                if isExterior then
                    local posId = this.getMarkerId(nil, dt.pos.x, dt.pos.y, "markerText")
                    local free = true

                    local maxDist = dt.fName == dt.name and 1536 or 6144
                    local steps = math.ceil(maxDist / eps)

                    local function check()
                        local x, y = math.floor(dt.pos.x / eps), math.floor(dt.pos.y / eps)
                        for i = x - steps, x + steps do
                            for j = y - steps, y + steps do
                                local popList = populationMap[string.format("%d_%d", i, j)]
                                if popList then
                                    for _, d in pairs(popList.m) do
                                        if d.name ~= dt.name and commonData.distance2D(d.pos, dt.pos) < maxDist then
                                            free = false
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                    check()

                    if free then
                        freeMarkers[posId] = true
                    end
                end
            end
        end

        entranceByLine = tableLib.values(entranceByLine, function (a, b)
            return a[1].line < b[1].line
        end)

        local function getAnchorOverlap(anchor, linePosData, textWidth, textHeight)
            textHeight = textHeight or charHeight
            local pos = linePosData.pos
            local baseYPos = pos.y + anchor.y * textHeight
            local line0Id = math.floor((baseYPos - textHeight) / lineHeight)
            local line1Id = math.ceil((baseYPos) / lineHeight)
            local s = pos.x - anchor.x * textWidth
            local e = pos.x + (1 - anchor.x) * textWidth
            if anchor.x == 0 then s = s + textHeight end
            if anchor.x == 1 then e = e - textHeight end

            local overlap = 0
            local collusions = {}
            for i = line0Id, line1Id do
                local intervals = textLines[i]
                if intervals then
                    for _, interv in ipairs(intervals) do
                        local os = math.max(s, interv[1])
                        local oe = math.min(e, interv[2])
                        if os < oe then
                            overlap = overlap + (oe - os)
                            if interv[3] then
                                collusions[interv[3]] = true
                            end
                        end
                    end
                end
            end

            return overlap, line0Id, line1Id, s, e, collusions
        end

        ---@type table<advancedWorldMap.ui.mapElementMeta, table<advancedWorldMap.ui.mapElementMeta, boolean>>
        local markerCollusions = {}

        for i = 1, #entranceByLine do
            local lineDt = entranceByLine[i]

            for j, data in ipairs(lineDt) do
                local dt = data.dt
                local mInfo = data.mInfo

                local textId = this.getMarkerId(cellId, dt.pos.x, dt.pos.y, "markerText")
                local isFree = freeMarkers[textId] == true

                local textMarkerHandler = this.markerById[textId]

                local isTileDiscovered = cellId ~= nil or not config.data.tileset.onlyDiscovered or discoveredLocs.isDiscovered(dt.cId)
                local isTileDiscoveredStateEqual = textMarkerHandler and isTileDiscovered == textMarkerHandler:getUserData().isTileDiscovered or false

                if doGroup and textMarkerHandler and not ungrouped[dt] and isTileDiscoveredStateEqual then
                    markerByData[dt] = textMarkerHandler
                    mInfo.textMarker = textMarkerHandler
                    goto continue
                end

                local textAnchor = entranceAnchors[1]
                local text = "  "..dt.name.."  "
                local textWidth = charHeight * stringLib.length(dt.name) * 0.6 * (isFree and freeMarkerMul or 1)
                local textHeight = charHeight * (isFree and freeMarkerMul or 1)

                local possibleAnchorsData = {}
                for k, anchor in ipairs(entranceAnchors) do
                    local d = {
                        anchor,
                        getAnchorOverlap(anchor, dt, textWidth, textHeight),
                    }
                    table.insert(possibleAnchorsData, d)
                    if d[2] == 0 then break end
                end

                local best = possibleAnchorsData[1]
                for _, res in ipairs(possibleAnchorsData) do
                    if res[2] == 0 then
                        best = res
                        break
                    elseif res[2] < best[2] then
                        best = res
                    end
                end

                textAnchor = best[1]

                local cId = dt.dCId
                this.markersByName[dt.name] = this.markersByName[dt.name] or {}

                local isCellDiscovered = not config.data.legend.onlyDiscovered or discoveredLocs.isDiscovered(cId)

                local color, backgroundColor, hasLocalTexture
                if isExterior then
                    color, backgroundColor, hasLocalTexture = getWorldMarkerColor(dt.cId, cId, dt.pos)
                elseif discoveredLocs.isDiscovered(dt.dCId) then
                    if discoveredLocs.isVisited(dt.dCId) then
                        color = config.data.ui.defaultLightColor
                    else
                        color = config.data.ui.markerDefaultColor
                    end
                else
                    color = config.data.ui.defaultDarkColor
                end
                backgroundColor = backgroundColor or config.data.ui.markerBackgroundColor
                local backgroundAlpha = hasLocalTexture and config.data.legend.alpha.background or
                    (config.data.legend.alpha.backgroundAlt or config.data.legend.alpha.background) * 0.01

                if not isTileDiscoveredStateEqual and config.data.legend.localMarkerBackground and textMarkerHandler then
                    local mBgColor = textMarkerHandler._params.textBackgroundColor
                    local mBgAlpha = textMarkerHandler._params.textBackgroundAlpha
                    if backgroundAlpha ~= mBgAlpha or backgroundColor.r ~= mBgColor.r or backgroundColor.g ~= mBgColor.g
                            or backgroundColor.b ~= mBgColor.b then
                        textMarkerHandler:destroy()
                        textMarkerHandler = nil ---@diagnostic disable-line: cast-local-type
                    end
                end

                local fontSize = math.floor(config.data.legend.markerSize * (isFree and freeMarkerMul or 1))
                local pos = dt.pos
                local alpha = config.data.legend.alpha.entrance * 0.01
                local userData

                if textMarkerHandler and textMarkerHandler:getUserData().grouped == doGroup and
                        isTileDiscoveredStateEqual then
                    local params = textMarkerHandler._params
                    local anchor = params.anchor or util.vector2(0, 0)
                    local isEqual = params.text == text and
                        anchor.x == textAnchor.x and anchor.y == textAnchor.y and
                        params.alpha == alpha and
                        params.fontSize == fontSize and
                        params.visible == isCellDiscovered and
                        params.pos.x == pos.x and params.pos.y == pos.y
                    if isEqual then
                        goto nextStep
                    end
                end

                userData = textMarkerHandler and textMarkerHandler:getUserData() or {
                    type = commonData.doorDescrMarkerType,
                    cellId = dt.dCId,
                    hash = dt.dHash,
                    searchText = stringLib.utf8_lower(dt.name),
                    fullName = dt.fName,
                    allowSearchFilter = true,
                    imageMarker = nil,
                    linkedImageMarkers = {},
                }
                userData.anchor = textAnchor
                userData.useWorldColor = not hasLocalTexture
                userData.textWidth = textWidth
                userData.textHeight = textHeight
                userData.isTileDiscovered = isTileDiscovered

                ---@diagnostic disable-next-line: cast-local-type
                textMarkerHandler = widget:createTextMarker{
                    id = textId,
                    useCache = true,
                    layerId = widget.LAYER.nonInteractive,
                    text = text,
                    alpha = alpha,
                    anchor = textAnchor,
                    fontSize = fontSize,
                    pos = dt.pos,
                    color = color,
                    showWhenZoomedIn = true,
                    visible = isCellDiscovered,
                    update = true,
                    textBackground = config.data.legend.localMarkerBackground,
                    textBackgroundColor = backgroundColor,
                    textBackgroundAlpha = backgroundAlpha,
                    userData = userData,
                }

                if not textMarkerHandler then goto continue end

                do
                    local registeredCIds = {}
                    for _, clusterEntry in ipairs(mInfo.entries) do
                        local entryCId = clusterEntry.dCId
                        if not registeredCIds[entryCId] then
                            registeredCIds[entryCId] = true
                            this.entranceMarkersByDestCellId[entryCId] = this.entranceMarkersByDestCellId[entryCId] or {}
                            this.entranceMarkersByDestCellId[entryCId][textId] = textMarkerHandler
                        end
                    end

                    this.markersByName[dt.name][textId] = textMarkerHandler
                    this.markersByDoorHash[dt.dHash] = this.markersByDoorHash[dt.dHash] or {}
                    this.markersByDoorHash[dt.dHash][textId] = textMarkerHandler
                    if disabledDoors.contains(dt.dHash) then
                        updateDoorMarkerVisibility(textMarkerHandler, false)
                    end
                    this.markerById[textId] = textMarkerHandler
                    textMarkerHandler:getUserData().grouped = false
                end

                ::nextStep::

                mInfo.textMarker = textMarkerHandler
                markerByData[dt] = textMarkerHandler
                for k = best[3], best[4] do
                    textLines[k] = textLines[k] or {}
                    table.insert(textLines[k], {best[5], best[6], textMarkerHandler})
                    if next(best[7]) then
                        markerCollusions[textMarkerHandler] = best[7]
                    end
                end

                ::continue::
            end
        end

        ---@param markerHandler advancedWorldMap.ui.mapElementMeta
        ---@param collusions table<advancedWorldMap.ui.mapElementMeta, boolean>
        local function resolveCollusions(markerHandler, collusions)
            local function getBounds(marker, anchor)
                local pos = marker._params.pos
                local textWidth = marker:getUserData().textWidth
                local textHeight = marker:getUserData().textHeight
                local baseYPos = pos.y + anchor.y * textHeight
                local minY = baseYPos - textHeight
                local maxY = baseYPos
                local minX = pos.x - anchor.x * textWidth
                local maxX = pos.x + (1 - anchor.x) * textWidth
                if anchor.x == 0 then minX = minX + textHeight end
                if anchor.x == 1 then maxX = maxX - textHeight end
                return minX, maxX, minY, maxY
            end

            local function getOverlapArea(minX1, maxX1, minY1, maxY1, minX2, maxX2, minY2, maxY2)
                local left = math.max(minX1, minX2)
                local right = math.min(maxX1, maxX2)
                local bottom = math.max(minY1, minY2)
                local top = math.min(maxY1, maxY2)
                if left < right and bottom < top then
                    return (right - left) * (top - bottom)
                end
                return 0
            end

            for colMarker, _ in pairs(collusions) do
                local minX1, maxX1, minY1, maxY1 = getBounds(markerHandler, markerHandler._params.anchor)
                local minX2, maxX2, minY2, maxY2 = getBounds(colMarker, colMarker._params.anchor)

                local currentArea = getOverlapArea(minX1, maxX1, minY1, maxY1, minX2, maxX2, minY2, maxY2)
                if currentArea > 0 then
                    local bestAnchor1 = markerHandler._params.anchor
                    local bestAnchor2 = colMarker._params.anchor
                    local bestArea = currentArea

                    for _, a1 in ipairs(entranceAnchors) do
                        local nx1, nx2, ny1, ny2 = getBounds(markerHandler, a1)
                        for _, a2 in ipairs(entranceAnchors) do
                            local nox1, nox2, noy1, noy2 = getBounds(colMarker, a2)
                            local area = getOverlapArea(nx1, nx2, ny1, ny2, nox1, nox2, noy1, noy2)
                            if area < bestArea then
                                bestArea = area
                                bestAnchor1 = a1
                                bestAnchor2 = a2
                                if bestArea == 0 then break end
                            end
                        end
                        if bestArea == 0 then break end
                    end

                    markerHandler._params.anchor = bestAnchor1
                    markerHandler._container.props.anchor = bestAnchor1

                    colMarker._params.anchor = bestAnchor2
                    colMarker._container.props.anchor = bestAnchor2
                end
            end
        end

        if not doGroup then
            for marker, collusions in pairs(markerCollusions) do
                resolveCollusions(marker, collusions)
            end
        end

    end

    for _, lst in pairs(entrancesData) do
    for _, dt in pairs(lst) do
        local imId = this.getMarkerId(cellId, dt.pos.x, dt.pos.y, "marker")
        local imageMarkerHandler = this.markerById[imId]

        local isTileDiscovered = cellId ~= nil or not config.data.tileset.onlyDiscovered or discoveredLocs.isDiscovered(dt.cId)
        local isTileDiscoveredStateEqual = imageMarkerHandler and isTileDiscovered == imageMarkerHandler:getUserData().isTileDiscovered or false

        if imageMarkerHandler and isTileDiscoveredStateEqual then
            imageMarkerHandler:setAlpha(imageMarkerHandler:getAlpha())
            goto continue
        end

        local mInfo = dataForTextMarkers[dt]
        local textMarkerHandler = mInfo and mInfo.textMarker or nil

        local cId = dt.dCId
        this.entranceMarkersByDestCellId[cId] = this.entranceMarkersByDestCellId[cId] or {}
        this.markersByName[dt.name] = this.markersByName[dt.name] or {}
        this.markersByDoorHash[dt.dHash] = this.markersByDoorHash[dt.dHash] or {}

        local isCellDiscovered = not config.data.legend.onlyDiscovered or discoveredLocs.isDiscovered(cId)

        local color, _, hasLocalTexture
        if isExterior then
            color, _, hasLocalTexture = getWorldMarkerColor(dt.cId, cId, dt.pos)
        elseif discoveredLocs.isDiscovered(dt.dCId) then
            if discoveredLocs.isVisited(dt.dCId) then
                color = config.data.ui.defaultLightColor
            else
                color = config.data.ui.markerDefaultColor
            end
        else
            color = config.data.ui.defaultDarkColor
        end

        local userData = imageMarkerHandler and imageMarkerHandler:getUserData() or {
            type = commonData.doorMarkerType,
            cellId = dt.dCId,
            hash = dt.dHash,
            searchText = stringLib.utf8_lower(dt.name),
            allowSearchFilter = true,
            textMarker = textMarkerHandler,
            name = dt.name,
            fullName = dt.fName,
        }

        userData.useWorldColor = not hasLocalTexture
        userData.isTileDiscovered = isTileDiscovered

        ---@diagnostic disable-next-line: cast-local-type
        imageMarkerHandler = widget:createImageMarker{
            id = imId,
            texture = dt.isDLEx and mapMarker45Texture or mapMarkerTexture,
            color = color,
            useCache = true,
            layerId = widget.LAYER.marker,
            alpha = config.data.legend.alpha.entrance * 0.01,
            anchor = util.vector2(0.5, 0.5),
            size = util.vector2(config.data.legend.markerSize, config.data.legend.markerSize),
            pos = dt.pos,
            showWhenZoomedIn = true,
            update = true,
            visible = isCellDiscovered,
            userData = userData,
            events = {
                mouseRelease = function (e, layout, pressed)
                    if e.button ~= 1 or not pressed or not this.activeMenuMeta then return end
                    if eventSys.triggerEvent(eventSys.EVENT.onMarkerClick, {marker = imageMarkerHandler}) then
                        return
                    end

                    this.activeMenuMeta:updateMapWidgetCell(dt.dCId)
                    if this.activeMenuMeta.mapWidget and dt.dPos then
                        this.activeMenuMeta.mapWidget:focusOnWorldPosition(dt.dPos)
                        this.activeMenuMeta.mapWidget:updateMarkers(true)
                    end

                    eventSys.triggerEvent(eventSys.EVENT.onMarkerClicked, {marker = imageMarkerHandler})
                    this.activeMenuMeta:update()
                end,

                mouseMove = function(e, layout)
                    if not tooltip.isExists(layout) then
                        local tooltipContent = ui.content{}
                        if eventSys.triggerEvent(eventSys.EVENT.onMarkerTooltipShow, {content = tooltipContent, marker = imageMarkerHandler}) then
                            return
                        end

                        if #tooltipContent > 0 then
                            local newTooltipContent = ui.content{}
                            for i = 1, #tooltipContent - 1 do
                                local item = tooltipContent[i]
                                newTooltipContent:add(item)
                                newTooltipContent:add(interval(0, config.data.ui.fontSize / 3))
                            end
                            newTooltipContent:add(tooltipContent[#tooltipContent])

                            layout.userData.tooltipContent = newTooltipContent
                            tooltip.createOrMove(e, layout, newTooltipContent)
                        else
                            layout.userData.tooltipContent = nil
                        end
                    elseif tooltip.createOrMove(e, layout) then
                        eventSys.triggerEvent(eventSys.EVENT.onMarkerTooltipShowed, {
                            marker = imageMarkerHandler,
                            content = layout.userData.tooltipContent,
                            tooltip = tooltip.get(layout)
                        })
                    end
                end,
            },
        }

        if imageMarkerHandler then
            this.entranceMarkersByDestCellId[cId][imId] = imageMarkerHandler
            this.markersByName[dt.name][imId] = imageMarkerHandler
            this.markersByDoorHash[dt.dHash][imId] = imageMarkerHandler
            if disabledDoors.contains(dt.dHash) then
                updateDoorMarkerVisibility(imageMarkerHandler, false)
            end
            this.markerById[imId] = imageMarkerHandler

            if textMarkerHandler then
                local userData = textMarkerHandler:getUserData()
                if userData then
                    userData.imageMarker = imageMarkerHandler
                    userData.linkedImageMarkers[imageMarkerHandler._id] = imageMarkerHandler
                end
            end
        end

        ::continue::
    end
    end

    if groupClusters then
        for _, cluster in pairs(groupClusters) do
            local count = #cluster.c
            if count < 3 then goto continue end

            ---@type table<string, advancedWorldMap.ui.mapElementMeta>[]
            local quadrants = {{}, {}, {}, {}}

            for _, dt in pairs(cluster.c) do
                local marker = markerByData[dt]
                if not marker then goto continue end

                local pos = marker._params.pos
                if pos.x >= cluster.bb.center.x and pos.y >= cluster.bb.center.y then
                    quadrants[2][marker._params.text] = marker
                elseif pos.x < cluster.bb.center.x and pos.y >= cluster.bb.center.y then
                    quadrants[1][marker._params.text] = marker
                elseif pos.x < cluster.bb.center.x and pos.y < cluster.bb.center.y then
                    quadrants[3][marker._params.text] = marker
                else
                    quadrants[4][marker._params.text] = marker
                end

                ---@diagnostic disable-next-line: missing-fields
                marker:updateLayout{
                    alpha = 0,
                }

                local linkedMarkers = marker:getUserData().linkedImageMarkers
                if linkedMarkers then
                    for _, h in pairs(linkedMarkers) do
                        local defaultAlpha = h:getAlpha()
                        h._container.props.alpha = defaultAlpha / 3
                    end
                end

                ::continue::
            end

            for qn, quadrant in ipairs(quadrants) do
                quadrants[qn] = tableLib.values(quadrant, qn <= 2 and
                    function (a, b)
                        return (a._params.pos.y < b._params.pos.y)
                    end or
                    function (a, b)
                        return (a._params.pos.y > b._params.pos.y)
                    end
                )
            end

            local quadrantSize = util.vector2(
                (cluster.bb.y.x - cluster.bb.x.x) / 2,
                (cluster.bb.y.y - cluster.bb.x.y) / 2
            ) + util.vector2(fontInWorldCoords, fontInWorldCoords) * 8

            local newFontWorldSize = fontInWorldCoords
            local newFontSize = config.data.legend.markerSize

            for qn, quadrant in ipairs(quadrants) do
                if not next(quadrant) then goto continue end
                local c = #quadrant
                local columns = c <= 5 and 1 or math.ceil((c * newFontWorldSize) / quadrantSize.y)
                columns = util.clamp(columns, 1, 3)
                local columnWidth = columns == 1 and 999999 or quadrantSize.x / columns
                columnWidth = math.max(newFontWorldSize * 8 * config.data.ui.textHeightMul, columnWidth)
                local textMaxLength = columns <= 1 and 99 or math.floor(columnWidth / (newFontWorldSize * config.data.ui.textHeightMul))
                textMaxLength = math.max(8, textMaxLength)

                local qAnchor = util.vector2(
                    (qn == 1 or qn == 3) and 1 or 0,
                    (qn > 2) and 1 or 0
                )
                local posMulY = (qn <= 2) and 1 or -1
                local posMulX = (qn == 1 or qn == 3) and -1 or 1
                for i, marker in ipairs(quadrant) do

                    local center = cluster.bb.center
                    ---@diagnostic disable-next-line: missing-fields
                    marker:updateLayout{
                        anchor = qAnchor,
                        pos = center + util.vector2((i % columns) * columnWidth * posMulX, (math.floor(i / columns)) *
                            newFontWorldSize * posMulY),
                        fontSize = newFontSize,
                        alpha = marker:getAlpha(),
                        text = stringLib.utf8_sub(marker._params.text, 2, textMaxLength) ..
                            ((stringLib.length(marker._params.text) - 2) > textMaxLength and "..." or "")
                    }

                    marker:getUserData().grouped = true
                end

                ::continue::
            end

            ::continue::
        end
    end

    widget:update()
end


local lastMarkerUpdate = 0
local function updateMarkers(e, preventTimeUpdate)
    local mapWidget = e.mapWidget
    if not mapWidget.cellId and not mapWidget:isInZoomInMode() then return end

    local cells = {}
    if not mapWidget.cellId then
        local region = e.region
        for x = math.floor(region.left / 8192), math.floor(region.right / 8192) do
            for y = math.floor(region.bottom / 8192), math.floor(region.top / 8192) do
                local cId = cellLib.getCellIdByGrid(x, y)
                cells[cId] = true
            end
        end
    else
        cells[mapWidget.cellId] = true
    end

    createMarkers(mapWidget, mapWidget.cellId, cells)

    if not preventTimeUpdate then
        lastMarkerUpdate = core.getRealTime()
    end
end
eventSys.registerHandler(eventSys.EVENT.onZoomMarkersUpdated, updateMarkers, 100000)


eventSys.registerHandler(eventSys.EVENT.onZoomed, function (e)
    if core.getRealTime() - lastMarkerUpdate > 2 then
        updateMarkers({mapWidget = e.mapWidget, region = e.mapWidget.onZoomMarkersRect}, true)
    end
end)


eventSys.registerHandler(eventSys.EVENT.onMarkerTooltipShow, function (e)
    local screenSize = uiUtils.getScaledScreenSize()
    local userData = e.marker:getUserData()
    if not userData then return end

    local text = userData.fullName or ""
    local tooltipWidth = math.max(250,
        math.min(screenSize.x / 5, stringLib.length(text) * config.data.ui.fontSize * config.data.ui.textHeightMul))

    e.content:add{
        type = ui.TYPE.TextEdit,
        props = {
            text = text,
            textColor = config.data.ui.defaultColor,
            textSize = config.data.ui.fontSize * 1.1,
            anchor = util.vector2(0.5, 0),
            size = util.vector2(tooltipWidth, 0),
            multiline = true,
            wordWrap = true,
            textAlignH = ui.ALIGNMENT.Center,
            textAlignV = ui.ALIGNMENT.Center,
            readOnly = true,
            autoSize = true,
        },
    }
end, 10000)


eventSys.registerHandler(eventSys.EVENT.onMapDestroyed, function (e)
    for _, marker in pairs(e.mapWidget:getRegisteredMarkers()) do
        if not marker.id or not this.markerById[marker.id] then goto continue end

        this.markerById[marker.id] = nil

        if marker.text then
            local markers = this.markersByName[marker.text]
            if markers then
                this.markersByName[marker.text][marker.id] = nil
            end
        end

        if not marker.userData then goto continue end

        if marker.userData.hash then
            this.markersByDoorHash[marker.userData.hash] = nil
        end

        if marker.userData.cellId then
            this.entranceMarkersByDestCellId[marker.userData.cellId] = nil
        end

        ::continue::
    end
end)


eventSys.registerHandler(eventSys.EVENT.onMarkerTooltipShow, function (e)
    local screenSize = uiUtils.getScaledScreenSize()
    local userData = e.marker:getUserData()
    if not userData then return end

    local lastVisited = discoveredLocs.isVisited(userData.cellId or "")
    if lastVisited then
        local lastVisitedText = l10n("LastVisited"):format(dateLib.getDateByTime(lastVisited))
        local width = math.max(250,
            math.min(screenSize.x / 5, stringLib.length(lastVisitedText) * config.data.ui.fontSize * config.data.ui.textHeightMul))

        e.content:add{
            type = ui.TYPE.TextEdit,
            props = {
                text = l10n("LastVisited"):format(dateLib.getDateByTime(lastVisited)),
                textColor = config.data.ui.defaultDarkColor,
                textSize = config.data.ui.fontSize,
                anchor = util.vector2(0.5, 0),
                size = util.vector2(width, 0),
                multiline = true,
                wordWrap = true,
                textAlignH = ui.ALIGNMENT.Center,
                textAlignV = ui.ALIGNMENT.Center,
                readOnly = true,
                autoSize = true,
            },
        }
    end
end, -1000)


eventSys.registerHandler(eventSys.EVENT.onMenuOpened, function (e)
    this.activeMenuMeta = e.menu
end)

eventSys.registerHandler(eventSys.EVENT.onMapInitialized, function (e)
    if e.cellId ~= nil then return end
    createWorldMarkers(e.mapWidget)
end)


return this