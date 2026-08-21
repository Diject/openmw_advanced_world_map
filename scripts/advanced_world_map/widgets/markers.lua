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

---@type advancedWorldMap.ui.mapElementMeta[]
local temporaryMarkers = {}

---@type table<string, any>
local bestAnchorCache = {}
local bestAnchorCacheZoom = nil



---@param newDiscovered string[]
function this.updateDiscovered(newDiscovered)
    if not this.markersByName or not this.entranceMarkersByDestCellId then return end

    local function updateVisibility(handler)
        local userData = handler:getUserData()
        if not userData then return end
        userData.discovered = true
        if not userData.disabled and not userData.filtered and not userData.clustered then
            handler:setVisibility(true)
        else
            handler:updateParams{visible = true} ---@diagnostic disable-line: missing-fields
        end
    end

    local addedSecondPrefixes = {}
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

                if userData.sPref and not addedSecondPrefixes[userData.sPref] then
                    table.insert(newDiscovered, userData.sPref)
                    addedSecondPrefixes[userData.sPref] = true
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

        local tempMrk = temporaryMarkers[name]
        if tempMrk then
            updateVisibility(tempMrk)
            tempMrk:setColor(tempMrk:getUserData().useWorldColor and config.data.ui.worldDefaultColor or
                config.data.ui.markerDefaultColor)
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
            bb = mapDataHandler.getClusterBoundingBox(cluster)
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

    util.vector2(0.5, -2.5),
    util.vector2(0, 2.5),
    util.vector2(1, 2.5),
    util.vector2(0.5, 3.5),

    util.vector2(-0.25, 2),
    util.vector2(1.25, 2),
    util.vector2(-0.25, -1),
    util.vector2(1.25, -1),

    util.vector2(-0.25, 3),
    util.vector2(1.25, 3),
    util.vector2(-0.25, -2),
    util.vector2(1.25, -2),
}

---@type advancedWorldMap.ui.mapWidget.region
local lastExRect = {bottom = 0, top = 0, left = 0, right = 0}
local lastExZoom = nil
local lastInZoom = nil
local lastCellId = true

--- gl to understand what is going on here.
--- This function is responsible for creating markers on the map widget based on the provided rect.
--- It handles grouping of markers, determining visibility based on discovery status, and managing anchor positions for text markers.
---@param widget advancedWorldMap.ui.mapWidgetMeta
---@param cellId string?
---@param allowedCells table<string, boolean>?
---@param region advancedWorldMap.ui.mapWidget.region?
local function createMarkers(widget, cellId, allowedCells, region)
    local newTemporaryMarkers = {}

    if eventSys.triggerEvent(eventSys.EVENT.onCellMarkersCreate, {mapWidget = widget, cellId = cellId}) then
        return
    end
    local entrances = mapDataHandler.entrances or {}

    -- constants

    local isExterior = cellId == nil
    local widgetZoom = widget.zoom
    local doGroup = isExterior and widgetZoom * 32 / widget.mapInfo.pixelsPerCell <= (config.data.legend.zoomToGroup / uiUtils.getUIScale())
    local doGroupToName = isExterior and doGroup and
        widgetZoom * 32 / widget.mapInfo.pixelsPerCell <= (config.data.legend.zoomToName / uiUtils.getUIScale())

    if bestAnchorCacheZoom ~= widgetZoom then
        bestAnchorCache = {}
        bestAnchorCacheZoom = widgetZoom
    end

    local targetZoom = allowedCells and widgetZoom or 30 / widget.eScale
    local fontInWorldCoords = widget.SCALE_FUNCTION.marker(config.data.legend.markerSize, targetZoom) * 8192 /
        (widget.mapInfo.pixelsPerCell * targetZoom * widget.eScale)
    local charHeight = fontInWorldCoords
    local lineHeight = cellId and charHeight / 10 or charHeight / 3
    local isolatedMarkerMul = 1.75
    local markerFontSize = config.data.legend.markerSize
    local isolatedFontSize = math.floor(markerFontSize * isolatedMarkerMul)
    local isolatedImageMarkerSize = util.vector2(config.data.legend.markerSize * 1.2, config.data.legend.markerSize * 1.2)
    local unisolatedImageMarkerSize = util.vector2(config.data.legend.markerSize * 0.65, config.data.legend.markerSize * 0.65)

    local anchorCacheMargin = fontInWorldCoords * 16
    local isAllowedToUseAnchorCache = region and
        (math.abs(region.right - region.left) > anchorCacheMargin * 2 or math.abs(region.top - region.bottom) > anchorCacheMargin * 2) or false

    local function isInAnchorCacheSafeRegion(pos)
        if not isAllowedToUseAnchorCache then return false end

        return pos.x >= region.left + anchorCacheMargin and pos.x <= region.right - anchorCacheMargin and ---@diagnostic disable-line: need-check-nil
            pos.y >= region.bottom + anchorCacheMargin and pos.y <= region.top - anchorCacheMargin ---@diagnostic disable-line: need-check-nil
    end

    local entrancesData = {}

    -- fill entrancesData with entrances that are in allowedCells or all entrances if cellId is nil
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

    local markersByParentHash = {}
    for _, lst in pairs(entrancesData) do
        for _, dt in pairs(lst) do
            if dt.pHash then
                markersByParentHash[dt.pHash] = markersByParentHash[dt.pHash] or {entries = {}}
                table.insert(markersByParentHash[dt.pHash].entries, dt)
            else
                markersByParentHash[dt.dHash] = markersByParentHash[dt.dHash] or {entries = {}}
                markersByParentHash[dt.dHash].dt = dt
            end
        end
    end

    ---@type table<integer, {dt: any, mInfo: any, line: integer, notParent: boolean?}[]>
    local entranceByLine = {}

    local populationMap = {}

    -- group entrances by their parent hash and assign them to lines based on their y position
    for h, listDt in pairs(markersByParentHash) do
        local dt = listDt.dt
        local notFoundParent = not dt or nil
        if listDt.dt then
            dt = listDt.dt
        else
            local _, eDt = next(listDt.entries)
            dt = eDt
        end
        if not dt then goto continue end

        for _, d in pairs(listDt.entries) do
            dataForTextMarkers[d] = listDt
        end
        dataForTextMarkers[dt] = listDt

        local line = math.floor(dt.pos.y / lineHeight)
        entranceByLine[line] = entranceByLine[line] or {}
        table.insert(entranceByLine[line], { line = line, dt = dt, mInfo = listDt, notParent = notFoundParent })

        ::continue::
    end

    local groupClusters
    ---@type table<string, {m: advancedWorldMap.dynamicDataHandler.entranceData[], cnt: number, pN: string, nLen: integer, bb: table}>
    local prefixNames
    local lastCreatedMarkerByName = {}

    -- create a grid of occupied intervals for each line based on the entrances' positions and sizes
    do
        ---@type {[1] : number, [2] : number}[][]
        local occupationIntervals = {}
        local ungrouped = {}

        -- create a population map to group entrances by their grid positions
        local eps = doGroup and 6 * fontInWorldCoords * config.data.ui.textHeightMul or 6144
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
                local threshold = doGroupToName and 2 or 6
                groupClusters = gridClustering(populationMap)
                for i, clusterDt in pairs(groupClusters) do
                    if clusterDt.cnt < threshold then
                        for _, dt in pairs(clusterDt.c) do
                            ungrouped[dt] = true
                        end
                        groupClusters[i] = nil
                    end
                end
            end
        end

        -- create occupation intervals for each line based on the entrances' positions and sizes
        for cId, lst in pairs(entrancesData) do
            for _, dt in pairs(lst) do
                local size = charHeight * 0.25
                local imgS = dt.pos.x - size
                local imgE = dt.pos.x + size
                local line0Id = math.floor((dt.pos.y - size) / lineHeight)
                local line1Id = math.ceil((dt.pos.y + size) / lineHeight)
                for i = line0Id, line1Id do
                    occupationIntervals[i] = occupationIntervals[i] or {}
                    table.insert(occupationIntervals[i], {imgS, imgE})
                end
            end
        end

        -- if grouping is enabled, create occupation intervals for the clusters and group them by name if doGroupToName
        if doGroup and groupClusters then
            local function addOccupiedRegion(sx, ex, sy, ey)
                local line0Id = math.floor(sy / lineHeight)
                local line1Id = math.ceil(ey / lineHeight)
                for i = line0Id, line1Id do
                    occupationIntervals[i] = occupationIntervals[i] or {}
                    table.insert(occupationIntervals[i], {sx, ex})
                end
            end

            prefixNames = {}
            for _, clusterDt in pairs(groupClusters) do
                if not doGroupToName then
                    addOccupiedRegion(clusterDt.bb.x.x - fontInWorldCoords * 5, clusterDt.bb.y.x + fontInWorldCoords * 5,
                        clusterDt.bb.x.y, clusterDt.bb.y.y)
                else
                    for _, dt in pairs(clusterDt.c) do
                        if dt.pN then
                            local pData = prefixNames[dt.ppN or dt.pN] or {cnt = 0, m = {}, pN = dt.pN}
                            table.insert(pData.m, dt)
                            pData.cnt = pData.cnt + 1
                            prefixNames[dt.ppN or dt.pN] = pData
                        end
                    end
                end
            end

            if doGroupToName then
                for n, prDt in pairs(prefixNames) do
                    local bb = mapDataHandler.getClusterBoundingBox(prDt.m)
                    prDt.bb = bb
                    local namelen = stringLib.length(n)
                    prDt.nLen = namelen
                    local center = bb.center
                    local hLen = math.ceil(namelen * 0.5)
                    addOccupiedRegion(center.x - fontInWorldCoords * hLen, center.x + fontInWorldCoords * hLen,
                        center.y - fontInWorldCoords, center.y + fontInWorldCoords)
                end
            end
        end

        -- calculate the overlap of a text marker with existing occupation intervals based on its anchor position and size
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
                local intervals = occupationIntervals[i]
                if intervals then
                    for _, interv in ipairs(intervals) do
                        local os = math.max(s, interv[1])
                        local oe = math.min(e, interv[2])
                        if os < oe then
                            overlap = overlap + (oe - os)
                            if interv[3] then
                                table.insert(collusions, interv[3])
                            end
                        end
                    end
                end
            end

            return overlap, line0Id, line1Id, s, e, collusions
        end

        ---@type table<advancedWorldMap.ui.mapElementMeta, table<advancedWorldMap.ui.mapElementMeta, boolean>>
        local markerCollusions = {}

        -- create text markers for each entrance, determining their anchor positions and visibility based on discovery status and grouping settings
        for _, lineDt in pairs(entranceByLine) do

            for j, data in ipairs(lineDt) do
                local dt = data.dt
                local mInfo = data.mInfo

                local textId = this.getMarkerId(cellId, dt.pos.x, dt.pos.y, "markerText")
                local isIsolated = dt.isIsl == true

                local textMarkerHandler = this.markerById[textId]

                local isTileDiscovered = cellId ~= nil or not config.data.tileset.onlyDiscovered or discoveredLocs.isDiscovered(dt.cId)
                local isTileDiscoveredStateEqual = textMarkerHandler and isTileDiscovered == textMarkerHandler:getUserData().isTileDiscovered or false

                local text = "  "..dt.name.."  "

                if textMarkerHandler then
                    textMarkerHandler:setVisibility(textMarkerHandler:getVisibility())
                end

                -- if grouping is enabled and the text marker already exists and is not ungrouped, use the existing text marker;
                -- otherwise, create a new text marker with the appropriate anchor position and visibility settings
                if doGroup and textMarkerHandler and not ungrouped[dt] and not isIsolated and isTileDiscoveredStateEqual and
                        text == textMarkerHandler._params.text then
                    mInfo.textMarker = textMarkerHandler
                    lastCreatedMarkerByName[textMarkerHandler:getUserData().name] = textMarkerHandler
                    goto continue
                end

                local textAnchor = entranceAnchors[1]
                local textWidth = charHeight * stringLib.length(dt.name) * 0.6 * (isIsolated and isolatedMarkerMul or 1)
                local textHeight = charHeight * (isIsolated and isolatedMarkerMul or 1)

                local bestAnchorData
                local lockAnchor = false
                local canUseCache = region ~= nil and isInAnchorCacheSafeRegion(dt.pos)

                -- if we can use the cache and have a cached anchor for this textId, use it; otherwise, find the best anchor by checking overlaps with existing markers
                if canUseCache and bestAnchorCache[textId] then
                    bestAnchorData = {
                        bestAnchorCache[textId],
                        getAnchorOverlap(bestAnchorCache[textId], dt, textWidth, textHeight),
                    }
                else
                    if not isExterior or not textMarkerHandler or not widget.isPointInRegion(lastExRect, dt.pos.x, dt.pos.y) then
                        for k, anchor in ipairs(entranceAnchors) do
                            local d = {
                                anchor,
                                getAnchorOverlap(anchor, dt, textWidth, textHeight),
                            }
                            if not bestAnchorData then
                                bestAnchorData = d
                            end

                            if d[2] == 0 then
                                bestAnchorData = d
                                break
                            elseif d[2] < bestAnchorData[2] then
                                bestAnchorData = d
                            end
                        end
                    else
                        local anchor = textMarkerHandler._params.anchor or util.vector2(0, 0)
                        bestAnchorData = {
                            anchor,
                            getAnchorOverlap(anchor, dt, textWidth, textHeight),
                        }
                        lockAnchor = true
                    end

                    if canUseCache and not lockAnchor then
                        bestAnchorCache[textId] = bestAnchorData[1]
                    end
                end
                textAnchor = bestAnchorData[1]

                -- if the best anchor has at least 2 collusions, shorten the text to fit within the available space
                if not lockAnchor and #bestAnchorData[7] >= 2 then
                    text = stringLib.utf8_sub(text, 2, 14)..((stringLib.length(text) - 2) > 14 and "..." or "")
                    textWidth = charHeight * (stringLib.length(text) - 2) * 0.6 * (isIsolated and isolatedMarkerMul or 1)
                end

                local cId = dt.dCId
                this.markersByName[dt.name] = this.markersByName[dt.name] or {}

                local isCellDiscovered = not config.data.legend.onlyDiscovered or discoveredLocs.isDiscovered(cId)

                -- determine the color and background color of the text marker based on whether it is in an exterior cell,
                -- whether the destination cell is discovered or visited, and whether there is a local texture for the world map
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
                local backgroundAlpha = hasLocalTexture and config.data.legend.alpha.background * 0.01 or
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

                local fontSize = isIsolated and isolatedFontSize or markerFontSize
                local pos = dt.pos
                local alpha = config.data.legend.alpha.entrance * 0.01
                local userData = textMarkerHandler and textMarkerHandler:getUserData()

                -- if the text marker already exists and has the same grouping and clustering settings,and the tile discovery state is the same,
                -- update its anchor lock status; otherwise, create a new text marker with the appropriate parameters
                if userData and (userData.grouped == doGroup or userData.clustered == doGroupToName) and
                        isTileDiscoveredStateEqual then
                    userData.anchorLocked = lockAnchor
                    local params = textMarkerHandler._params ---@diagnostic disable-line: need-check-nil
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

                -- if the text marker already exists, update its userData; otherwise, create a new userData
                userData = userData or {
                    type = commonData.doorDescrMarkerType,
                    cellId = dt.dCId,
                    hash = dt.dHash,
                    searchText = stringLib.utf8_lower(dt.name),
                    name = dt.name,
                    fullName = dt.fName,
                    allowSearchFilter = true,
                    imageMarker = nil,
                    linkedImageMarkers = {},
                }
                userData.anchor = textAnchor
                userData.anchorLocked = lockAnchor
                userData.useWorldColor = not widget.cellId and not hasLocalTexture and true or false
                userData.textWidth = textWidth
                userData.textHeight = textHeight
                userData.isTileDiscovered = isTileDiscovered
                userData.isIsolated = isIsolated

                -- create a new text marker with the specified parameters
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

                -- if the text marker was successfully created, update the relevant data structures to track it and its associated information
                do
                    this.entranceMarkersByDestCellId[dt.dCId] = this.entranceMarkersByDestCellId[dt.dCId] or {}
                    this.entranceMarkersByDestCellId[dt.dCId][textId] = textMarkerHandler

                    this.markersByName[dt.name][textId] = textMarkerHandler
                    this.markersByDoorHash[dt.dHash] = this.markersByDoorHash[dt.dHash] or {}
                    this.markersByDoorHash[dt.dHash][textId] = textMarkerHandler
                    if disabledDoors.contains(dt.dHash) then
                        updateDoorMarkerVisibility(textMarkerHandler, false)
                    end
                    this.markerById[textId] = textMarkerHandler
                    textMarkerHandler:getUserData().grouped = false
                    textMarkerHandler:getUserData().clustered = false

                    if data.notParent then
                        temporaryMarkers[textId] = nil
                        newTemporaryMarkers[textId] = textMarkerHandler
                    end
                end

                ::nextStep::

                mInfo.textMarker = textMarkerHandler
                lastCreatedMarkerByName[textMarkerHandler:getUserData().name] = textMarkerHandler
                for k = bestAnchorData[3], bestAnchorData[4] do
                    occupationIntervals[k] = occupationIntervals[k] or {}
                    table.insert(occupationIntervals[k], {bestAnchorData[5], bestAnchorData[6], textMarkerHandler})
                    if next(bestAnchorData[7]) then
                        markerCollusions[textMarkerHandler] = bestAnchorData[7]
                    end
                end

                ::continue::
            end
        end

        ---@param markerHandler advancedWorldMap.ui.mapElementMeta
        ---@param collusions advancedWorldMap.ui.mapElementMeta[]
        local function resolveCollusions(markerHandler, collusions)
            local isMainLocked = markerHandler:getUserData().anchorLocked

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

            for _, colMarker in pairs(collusions) do
                local isColludedLocked = colMarker:getUserData().anchorLocked
                if isColludedLocked and isMainLocked then
                    goto continue
                end
                local minX1, maxX1, minY1, maxY1 = getBounds(markerHandler, markerHandler._params.anchor)
                local minX2, maxX2, minY2, maxY2 = getBounds(colMarker, colMarker._params.anchor)

                local currentArea = getOverlapArea(minX1, maxX1, minY1, maxY1, minX2, maxX2, minY2, maxY2)
                local bestArea = currentArea
                if currentArea > 0 then
                    local bestAnchor1 = markerHandler._params.anchor
                    local bestAnchor2 = colMarker._params.anchor

                    for _, a1 in ipairs(entranceAnchors) do
                        local mAnchor = isMainLocked and bestAnchor1 or a1
                        local nx1, nx2, ny1, ny2 = getBounds(markerHandler, mAnchor)
                        for _, a2 in ipairs(entranceAnchors) do
                            local colAnchor = isColludedLocked and bestAnchor2 or a2
                            local nox1, nox2, noy1, noy2 = getBounds(colMarker, colAnchor)
                            local area = getOverlapArea(nx1, nx2, ny1, ny2, nox1, nox2, noy1, noy2)
                            if area < bestArea then
                                bestArea = area
                                bestAnchor1 = mAnchor
                                bestAnchor2 = colAnchor
                                if bestArea == 0 then break end
                            end
                            if isColludedLocked then break end
                        end
                        if bestArea == 0 or isMainLocked then break end
                    end

                    markerHandler._params.anchor = bestAnchor1
                    markerHandler._container.props.anchor = bestAnchor1

                    colMarker._params.anchor = bestAnchor2
                    colMarker._container.props.anchor = bestAnchor2
                end

                ::continue::
            end
        end

        -- if grouping is not enabled, resolve collusions for each marker and its associated collusions
        if not doGroup then
            for marker, collusions in pairs(markerCollusions) do
                resolveCollusions(marker, collusions)
            end
        end

    end

    -- create image markers for each entrance
    for _, lst in pairs(entrancesData) do
    for _, dt in pairs(lst) do
        local imId = this.getMarkerId(cellId, dt.pos.x, dt.pos.y, "marker")
        local imageMarkerHandler = this.markerById[imId]

        local isTileDiscovered = cellId ~= nil or not config.data.tileset.onlyDiscovered or discoveredLocs.isDiscovered(dt.cId)
        local isTileDiscoveredStateEqual = imageMarkerHandler and isTileDiscovered == imageMarkerHandler:getUserData().isTileDiscovered or false

        -- if the image marker already exists and has the same tile discovery state, update its alpha; otherwise, create a new image marker
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
            sPref = doGroupToName and dt.ppN or nil
        }

        userData.useWorldColor = not widget.cellId and not hasLocalTexture and true or false
        userData.isTileDiscovered = isTileDiscovered

        local isIsolated = textMarkerHandler and textMarkerHandler:getUserData().isIsolated or false
        local markerSize = isIsolated and isolatedImageMarkerSize or unisolatedImageMarkerSize

        ---@diagnostic disable-next-line: cast-local-type
        imageMarkerHandler = widget:createImageMarker{
            id = imId,
            texture = dt.isDLEx and mapMarker45Texture or mapMarkerTexture,
            color = color,
            useCache = true,
            layerId = widget.LAYER.marker,
            alpha = config.data.legend.alpha.entrance * 0.01,
            anchor = util.vector2(0.5, 0.5),
            size = markerSize,
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

    -- hide a marker and its linked image markers if it is not isolated or if forceHide is true
    ---@param marker advancedWorldMap.ui.mapElementMeta
    local function hideMarker(marker, changeVisibility, forceHide)
        local userData = marker:getUserData()

        if not userData.isIsolated or forceHide then
            if changeVisibility then
                local visibility = marker:getVisibility()
                marker:setVisibility(false)
                marker._params.visible = visibility
            else
                marker:setVisibility(marker:getVisibility())
                marker._container.props.alpha = 0
            end
        end

        local linkedMarkers = userData.linkedImageMarkers
        if linkedMarkers then
            for _, h in pairs(linkedMarkers) do
                local defaultAlpha = h:getAlpha()
                h._container.props.alpha = defaultAlpha * 0.5
            end
        end
    end


    -- if grouping by name is enabled, process the prefix data for each group of entrances with the same name,
    -- creating a prefix line for each group and adjusting the font size and position based on the number of entrances in the group
    if doGroupToName then
        local prefixLines = {}
        local prefixLineHeight = widget.SCALE_FUNCTION.marker(40, targetZoom) * 8192 /
            (widget.mapInfo.pixelsPerCell * targetZoom * widget.eScale)

        local prefixCount = {}

        -- process the prefix data for a group of entrances with the same name,
        -- creating a prefix line and adjusting the font size and position based on the number of entrances in the group
        local function processPrefixData(name, pDt)
            local isDiscovered = discoveredLocs.isDiscovered(name)
            local isVisible = false
            local xc, yc = {}, {}
            local cnt = 0

            local function processMarker(marker, forceHide)
                hideMarker(marker, true, forceHide)

                if not isDiscovered then
                    isDiscovered = discoveredLocs.isDiscovered(marker:getUserData().cellId)
                end

                if not isVisible and not disabledDoors.contains(marker:getUserData().hash) then
                    isVisible = true
                end

                marker:getUserData().clustered = true
                marker:getUserData().grouped = false
            end

            for _, dt in pairs(pDt.m) do
                local mDt = dataForTextMarkers[dt]
                local marker = mDt and mDt.textMarker
                if marker then
                    processMarker(marker, marker:getUserData().name:find(name, 1, true) ~= nil)
                end

                local pos = dt.pos
                table.insert(xc, pos.x)
                table.insert(yc, pos.y)
                cnt = cnt + 1
            end
            local sameNameMarker = lastCreatedMarkerByName[name]
            if sameNameMarker then
                processMarker(sameNameMarker, true)
            end

            if not isVisible then return end

            prefixCount[pDt.pN] = (prefixCount[pDt.pN] or 0) + pDt.cnt

            table.sort(xc)
            table.sort(yc)
            local xCenter = 0
            local yCenter = 0
            local brd = math.floor(cnt * 0.25)
            local cCnt = 0
            for i = brd + 1, cnt - brd do
                xCenter = xCenter + xc[i]
                yCenter = yCenter + yc[i]
                cCnt = cCnt + 1
            end
            local center = util.vector2(xCenter / cCnt, yCenter / cCnt)

            local bb = pDt.bb
            local bbWidth = bb.y.x - bb.x.x

            local fontSizeMul = pDt.cnt > 3 and 2.5 or 1.5
            local fontSize = math.floor(config.data.legend.markerSize * fontSizeMul + math.min(64, bbWidth / 192, pDt.cnt * 0.5) * 0.25)
            fontSize = math.max(isolatedFontSize, fontSize)
            local fontSizeInWorldCoords = widget.SCALE_FUNCTION.marker(fontSize, targetZoom) * 8192 /
                (widget.mapInfo.pixelsPerCell * targetZoom * widget.eScale)

            local prefixLineId = math.floor(center.y / prefixLineHeight)
            prefixLines[prefixLineId] = prefixLines[prefixLineId] or {}
            table.insert(prefixLines[prefixLineId], {
                pos = center,
                fontSize = fontSize,
                name = name,
                isDiscovered = isDiscovered,
                halfHeight = fontSizeInWorldCoords * 0.5,
                halfWidth = fontSizeInWorldCoords * pDt.nLen * 0.7 * 0.5,
            })
        end

        -- process the prefix data for each group of entrances with the same name, first processing those that do not have a matching prefix name,
        -- and then processing those that do have a matching prefix name, creating prefix lines for each group and
        -- adjusting the font size and position based on the number of entrances in the group
        for name, pDt in pairs(prefixNames) do
            if pDt.pN ~= name then
                processPrefixData(name, pDt)
            end
        end

        for name, pDt in pairs(prefixNames) do
            if pDt.pN == name then
                if (prefixCount[pDt.pN] or 0) < pDt.cnt * 3 then
                    processPrefixData(name, pDt)
                elseif pDt.cnt > 2 then
                    for _, dt in pairs(pDt.m) do
                        local mDt = dataForTextMarkers[dt]
                        local marker = mDt and mDt.textMarker
                        if marker then
                            hideMarker(marker)
                        end
                    end
                end
            end
        end

        local prefixList = {}
        for _, lineDt in pairs(prefixLines) do
            for _, dt in pairs(lineDt) do
                table.insert(prefixList, dt)
            end
        end

        for k = 1, 5 do
            local moved = false
            for i = 1, #prefixList do
                local dt1 = prefixList[i]
                for j = i + 1, #prefixList do
                    local dt2 = prefixList[j]
                    if math.abs(dt1.pos.x - dt2.pos.x) < (dt1.halfWidth + dt2.halfWidth) and
                            math.abs(dt1.pos.y - dt2.pos.y) < (dt1.halfHeight + dt2.halfHeight) then

                        local overlapY = (dt1.halfHeight + dt2.halfHeight) - math.abs(dt1.pos.y - dt2.pos.y)
                        local shiftY = overlapY / 2 + 1

                        if dt1.pos.y < dt2.pos.y then
                            dt1.pos = util.vector2(dt1.pos.x, dt1.pos.y - shiftY)
                            dt2.pos = util.vector2(dt2.pos.x, dt2.pos.y + shiftY)
                        else
                            dt1.pos = util.vector2(dt1.pos.x, dt1.pos.y + shiftY)
                            dt2.pos = util.vector2(dt2.pos.x, dt2.pos.y - shiftY)
                        end
                        moved = true
                    end
                end
            end
            if not moved then break end
        end

        -- create text markers for each prefix line
        for _, dt in ipairs(prefixList) do
            local hasTexture = mapTextureHandler.isWorldLocalMapTextureExists(cellLib.getGridCoordinates(dt.pos))
            if config.data.tileset.onlyDiscovered and not discoveredLocs.isDiscovered(cellLib.getCellIdByPos(dt.pos)) then
                hasTexture = false
            end

            local color
            local shadowColor
            if dt.isDiscovered then
                color = hasTexture and config.data.ui.markerDefaultColor or config.data.ui.worldDefaultColor
                shadowColor = hasTexture and config.data.ui.markerBackgroundColor or config.data.ui.markerBackgroundAltColor
            else
                color = hasTexture and config.data.ui.defaultDarkColor or config.data.ui.worldDefaultDarkColor
                shadowColor = hasTexture and config.data.ui.markerBackgroundColor or config.data.ui.markerBackgroundAltColor
            end

            if temporaryMarkers[dt.name] then
                temporaryMarkers[dt.name]:destroy()
            end
            local newMarker = widget:createTextMarker{
                id = "_NGr_"..dt.name,
                update = true,
                layerId = widget.LAYER.name,
                text = dt.name,
                anchor = util.vector2(0.5, 0.5),
                pos = dt.pos,
                color = color,
                textBackground = config.data.legend.localMarkerBackground,
                textBackgroundColor = shadowColor,
                textBackgroundAlpha = config.data.legend.alpha.background * 0.008,
                textShadow = true,
                shadowColor = shadowColor,
                fontSize = dt.fontSize,
                scaleFunc = widget.SCALE_FUNCTION.marker,
                alpha = config.data.legend.alpha.entrance * 0.01,
                visible = not config.data.legend.onlyDiscovered or discoveredLocs.isDiscovered(dt.name) or dt.isDiscovered,
                showWhenZoomedIn = true,
                userData = {
                    type = commonData.cityRegionMarkerType,
                    searchText = stringLib.utf8_lower(dt.name),
                    allowSearchFilter = true,
                    useWorldColor = not hasTexture,
                }
            }
            temporaryMarkers[dt.name] = nil
            newTemporaryMarkers[dt.name] = newMarker
        end


    -- if grouping by name is not enabled but grouping is enabled, process the clusters of entrances
    elseif groupClusters then
        for _, cluster in pairs(groupClusters) do

            ---@type table<string, advancedWorldMap.ui.mapElementMeta>[]
            local quadrants = {{}, {}, {}, {}}

            -- sort the markers in the cluster into quadrants based on their position relative to the center of the cluster's bounding box
            for _, dt in pairs(cluster.c) do
                local mDt = dataForTextMarkers[dt]
                local marker = mDt and mDt.textMarker
                if not marker then goto continue end

                -- if the marker is not isolated, hide it and its linked image markers
                hideMarker(marker)

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
            ) + util.vector2(fontInWorldCoords, fontInWorldCoords) * 12

            local newFontWorldSize = fontInWorldCoords
            local newFontSize = config.data.legend.markerSize

            -- determine the number of columns and the maximum text length for each quadrant based on the number of markers in the quadrant and the size of the quadrant
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
                    -- update the layout of the marker
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
                    marker:getUserData().clustered = false
                end

                ::continue::
            end

            ::continue::
        end
    end

    for _, m in pairs(temporaryMarkers) do
        m:destroy()
    end
    temporaryMarkers = newTemporaryMarkers

    widget.userData.markersWereCreated = true
    widget:update()
end


local function updateMarkers(e)
    local mapWidget = e.mapWidget
    if not mapWidget.cellId and not mapWidget:isInZoomInMode() then return end

    if mapWidget.cellId or lastExZoom ~= mapWidget.zoom then
        lastExRect = {bottom = 0, top = 0, left = 0, right = 0}
        lastExZoom = mapWidget.zoom
    end

    if mapWidget.cellId and mapWidget.cellId == lastCellId and lastInZoom == mapWidget.zoom and
            mapWidget.userData.markersWereCreated then
        return
    end

    local cells = {}
    local region = e.region
    if not mapWidget.cellId then
        for x = math.floor(region.left / 8192), math.floor(region.right / 8192) do
            for y = math.floor(region.bottom / 8192), math.floor(region.top / 8192) do
                local cId = cellLib.getCellIdByGrid(x, y)
                cells[cId] = true
            end
        end
    else
        cells[mapWidget.cellId] = true
    end

    createMarkers(mapWidget, mapWidget.cellId, cells, region)

    if not mapWidget.cellId then
        lastExRect = e.region
    else
        lastInZoom = mapWidget.zoom
    end

    lastCellId = mapWidget.cellId
end
eventSys.registerHandler(eventSys.EVENT.onZoomMarkersUpdated, updateMarkers, 100000)


eventSys.registerHandler(eventSys.EVENT.onZoomed, function (e)
    if not e.mapWidget.cellId and not e.mapWidget.isRegionEqual(e.mapWidget.onZoomMarkersRect, lastExRect) then
        updateMarkers({mapWidget = e.mapWidget, region = e.mapWidget.onZoomMarkersRect})
    end
end)


eventSys.registerHandler("onMapShown", function (e)
    if not e.mapWidget.cellId and not e.mapWidget.isRegionEqual(e.mapWidget.onZoomMarkersRect, lastExRect) then
        updateMarkers({mapWidget = e.mapWidget, region = e.mapWidget.onZoomMarkersRect})
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

        local markerName = marker.userData.name
        if markerName then
            local markers = this.markersByName[markerName]
            if markers then
                this.markersByName[markerName][marker.id] = nil
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