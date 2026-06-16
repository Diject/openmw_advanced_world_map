local async = require("openmw.async")
local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")
local input = require('openmw.input')
local playerRef = require("openmw.self")

local commonData = require("scripts.advanced_world_map.common")
local config = require("scripts.advanced_world_map.config.configLib")

local uiUtils = require("scripts.advanced_world_map.ui.utils")
local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local cellLib = require("scripts.advanced_world_map.utils.cell")

local localStorage = require("scripts.advanced_world_map.storage.localStorage")
local mapDataHandler = require("scripts.advanced_world_map.mapDataHandler")
local playerPos = require("scripts.advanced_world_map.playerPosition")
local discoveredLocations = require("scripts.advanced_world_map.discoveredLocations")

local eventSys = require("scripts.advanced_world_map.eventSys")

local tooltip = require("scripts.advanced_world_map.ui.tooltip")
local scrollBox = require("scripts.advanced_world_map.ui.scrollBox")
local borders = require("scripts.advanced_world_map.ui.borders")
local button = require("scripts.advanced_world_map.ui.button")
local interval = require("scripts.advanced_world_map.ui.interval")
local checkBox = require("scripts.advanced_world_map.ui.checkBox")
local selector = require("scripts.advanced_world_map.ui.selector")

local l10n = core.l10n(commonData.l10nKey)

local defaultColor = util.color.rgb(0, 0, 0)

local searchIcoTexture = ui.texture{ path = commonData.searchWidgetIcon }

local worldMarkerTexture = ui.texture{ path = commonData.searchWorldMarkerPath }


---@type table<string, advancedWorldMap.ui.mapElementMeta>
local visibleMarkers = {}
---@type table<string, advancedWorldMap.ui.mapElementMeta>
local modifiedMarkers = {}
---@type table<any, advancedWorldMap.ui.mapElementMeta>
local temporaryMarkers = {}
---@type table<string, any[]> by pos hash
local searchData = {}
---@type table<string, boolean>
local targetCells = {}

local usePatternSearch = false


local searchModes = {
    Locations = "locations",
    Actors = "actors",
    Items = "items"
}


---@param handler advancedWorldMap.ui.mapElementMeta
local function getMarkerId(handler)
    return tostring(handler._parent.cellId).."_"..handler:getId()
end


---@return string
local function getPosHash(cellId, pos)
    return string.format("pos_%s_%d_%d", tostring(cellId), pos.x, pos.y)
end


---@param menu advancedWorldMap.ui.menu.map
local function createTemporaryMarker(id, mapWidget, menu, loc, pos, color, textTable, locNamesTable, showZoomIn)
    if temporaryMarkers[id] then return end

    local tooltipText = table.concat(tableLib.keys(textTable or {}), "; ")
    if locNamesTable and next(locNamesTable) then
        tooltipText = tooltipText.."\n\n"..table.concat(tableLib.keys(locNamesTable), " / ")
    end

    local h = mapWidget:createImageMarker{
        layerId = mapWidget.LAYER.marker,
        pos = pos,
        color = color or config.data.ui.foundMarkerColor,
        texture = worldMarkerTexture,
        anchor = util.vector2(0.5, 1),
        size = util.vector2(config.data.legend.markerSize * 2, config.data.legend.markerSize * 4),
        showWhenZoomedOut = true,
        showWhenZoomedIn = showZoomIn,
        tooltipContent = textTable and ui.content{
            {
                type = ui.TYPE.TextEdit,
                props = {
                    text = tooltipText,
                    textSize = config.data.ui.fontSize,
                    textColor = config.data.ui.defaultColor,
                    autoSize = true,
                    multiline = true,
                    wordWrap = true,
                    readOnly = true,
                    size = util.vector2(
                        util.clamp(
                            stringLib.length(tooltipText) * config.data.ui.fontSize * config.data.ui.textHeightMul,
                            300,
                            uiUtils.getScaledScreenSize().x / 5
                        ),
                        0
                    ),
                    textAlignH = ui.ALIGNMENT.Center,
                }
            }
        } or nil,
        events = {
            mouseRelease = function(e, layout, pressed)
                if e.button ~= 1 or not pressed then return end

                if menu.mapWidget.cellId ~= loc.id then
                    menu:updateMapWidgetCell(loc.id)
                end
                menu.mapWidget:focusOnWorldPosition(loc.pos)
                if not menu.mapWidget:isInZoomInMode() then
                    menu.mapWidget:setZoom(menu.mapWidget:getZoomModeThreshold() + 0.5)
                end
                menu.mapWidget:updateMarkers()

                menu:update()
            end,
        }
    }
    temporaryMarkers[id] = h
end


local function removeTemporaryMarkers()
    for i, handler in pairs(temporaryMarkers) do
        handler:destroy()
        temporaryMarkers[i] = nil
    end
end


---@param handler advancedWorldMap.ui.mapElementMeta
local function setMarkerVisibility(handler, val)
    if val == nil then
        handler:updateLayout{ ---@diagnostic disable-line: missing-fields
            visible = (handler._params.visible == true or handler._params.visible == nil) and true or false,
        }
        visibleMarkers[getMarkerId(handler)] = nil
    elseif val then
        handler:updateLayout{visible = val} ---@diagnostic disable-line: missing-fields
        visibleMarkers[getMarkerId(handler)] = handler
    end
end

local function resetMarkersVisibility()
    for i, handler in pairs(visibleMarkers) do
        setMarkerVisibility(handler)
        visibleMarkers[i] = nil
    end
end

---@param handler advancedWorldMap.ui.mapElementMeta
local function setMarkerColor(handler, color, reset)
    if not color and not reset then return end

    if reset then
        handler:updateLayout{ ---@diagnostic disable-line: missing-fields
            color = handler._params.color or defaultColor,
        }
        modifiedMarkers[getMarkerId(handler)] = nil
    else
        handler:updateLayout{ ---@diagnostic disable-line: missing-fields
            color = color,
        }
        modifiedMarkers[getMarkerId(handler)] = handler
    end
end

local function resetMarkersColor()
    for i, handler in pairs(modifiedMarkers) do
        setMarkerColor(handler, nil, true)
        modifiedMarkers[i] = nil
    end
end

---@param handler advancedWorldMap.ui.mapElementMeta
---@param textFilter string
local function updateLayoutForMarker(handler, textFilter)
    local userData = handler:getUserData()
    if not userData then return end

    if userData.allowSearchFilter then
        local posHash = getPosHash(handler._parent.cellId, handler._params.pos)
        local data = searchData[posHash]

        if data and next(data) then
            local params = data[1]
            setMarkerColor(handler, params.color or config.data.ui.defaultColor)
        elseif userData.searchText and (userData.searchText:find(textFilter, 1, true) or
                usePatternSearch and userData.searchText:find(textFilter)) then
            setMarkerColor(handler, config.data.ui.foundMarkerColor)
        end
    end
end

---@param mapWidget advancedWorldMap.ui.mapWidgetMeta
local function updateVisibilityForActiveMarkers(mapWidget, textFilter)
    local markers = mapWidget:getActiveMarkers()

    for _, handler in pairs(markers or {}) do
        updateLayoutForMarker(handler, textFilter)
    end
end


---@return table<string, string> res by cell id - cell name
local function getAvailableInteriorNamesFromInterior(cellId, checked, res)
    checked = checked or {}
    res = res or {}

    if checked[cellId] then return res end
    checked[cellId] = true

    for _, destDt in pairs(mapDataHandler.entrances[cellId] or {}) do
        if not checked[destDt.dCId] then
            if not destDt.isDEx then
                res[destDt.dCId] = destDt.name
                getAvailableInteriorNamesFromInterior(destDt.dCId, checked, res)
            end
        end
    end

    return res
end


---@return table<string, table<string, string>> res by destination cell id - by cell id - cell name
local function getAvailableExteriorNamesFromInterior(cellId, checked, res)
    checked = checked or {}
    res = res or {}

    if checked[cellId] then return res end
    checked[cellId] = true

    for _, destDt in pairs(mapDataHandler.entrances[cellId] or {}) do
        if not checked[destDt.dCId] then
            if destDt.isDEx then
                res[destDt.dCId] = res[destDt.dCId] or {}
                res[destDt.dCId][cellId] = destDt.name
            else
                getAvailableExteriorNamesFromInterior(destDt.dCId, checked, res)
            end
        end
    end

    return res
end


---@param cellId string
---@return table<string, advancedWorldMap.dynamicDataHandler.entranceData> res by pos hash
local function getWorldEntrancesForCell(cellId)
    local res = {}

    local exteriorCells = getAvailableExteriorNamesFromInterior(cellId)
    for exCellId, from in pairs(exteriorCells) do
        for _, dt in pairs(mapDataHandler.entrances[exCellId] or {}) do
            if from[dt.dCId] then
                res[getPosHash(nil, dt.pos)] = dt
            end
        end
    end

    return res
end


---@param menu advancedWorldMap.ui.menu.map
---@return {cellId : string?, pos : {x : number, y : number}, locations: table?, text : string, color : any, dist : number?, priority : number?}[]
local function getResults(menu, str, showUnrevealed, searchAllLocations)
    local res = {}

    local mapWidget = menu.mapWidget

    local entrances = mapDataHandler.entrances or {}

    local checked = {}
    local function processCell(cellId, isExterior, inInteriors)
        if checked[cellId] then return end
        checked[cellId] = true

        if isExterior == nil then isExterior = cellId:find(commonData.exteriorCellLabel, 1, true) and true or false end

        local doors = mapDataHandler.entrances[cellId]

        if not isExterior then
            local _, door = next(doors or {})
            ---@type advancedWorldMap.dynamicDataHandler.entranceData?
            local destCellDoor
            if door then
                for _, d in pairs(entrances[door.dCId] or {}) do
                    if d.dCId == cellId then
                        destCellDoor = d
                        break
                    end
                end
            end
            local name = destCellDoor and destCellDoor.name or mapDataHandler.cellNameById[cellId] or ""
            local nameLower = stringLib.utf8_lower(name)

            if (nameLower:find(str, 1, true) or usePatternSearch and nameLower:find(str)) and
                    (showUnrevealed or discoveredLocations.isDiscovered(cellId)) then

                local altPos = {x = 0, y = 0}
                if not destCellDoor and doors then
                    local cnt = #doors
                    for _, d in pairs(doors) do
                        altPos.x = altPos.x + d.pos.x
                        altPos.y = altPos.y + d.pos.y
                    end
                    altPos.x = altPos.x / cnt
                    altPos.y = altPos.y / cnt
                end

                table.insert(res, {
                    text = name,
                    cellId = destCellDoor and destCellDoor.cId or cellId,
                    pos = destCellDoor and destCellDoor.pos or altPos,
                    priority = 0,
                    color = config.data.ui.foundMarkerColor
                })
            end
        end

        if inInteriors then
            if isExterior then
                for _, dt in pairs(doors or {}) do
                    if checked[dt.dCId] then goto continue end
                    checked[dt.dCId] = true

                    local destNameLower = stringLib.utf8_lower(dt.name)
                    if (destNameLower:find(str, 1, true) or usePatternSearch and destNameLower:find(str)) and
                            (showUnrevealed or discoveredLocations.isDiscovered(dt.dCId)) then
                        table.insert(res, {
                            text = dt.fName,
                            cellId = not dt.isEx and dt.cId or nil,
                            pos = dt.pos,
                            priority = 0,
                            color = config.data.ui.foundMarkerColor
                        })
                        targetCells[dt.dCId] = true
                    end

                    ::continue::
                end
            end

            for cId, cellName in pairs(getAvailableInteriorNamesFromInterior(cellId)) do
                processCell(cId, false, false)
            end
        end
    end


    if not searchAllLocations then
        if mapWidget.cellId then
            processCell(mapWidget.cellId, false, true)
        else
            for cellId, list in pairs(entrances) do
                if not cellId:find(commonData.exteriorCellLabel, 1, true) then
                    goto continue
                end

                processCell(cellId, true, true)

                ::continue::
            end

            local names = mapDataHandler.cellNameData
            for name, dt in pairs(names) do
                local nameLower = stringLib.utf8_lower(name)
                if (nameLower:find(str, 1, true) or usePatternSearch and nameLower:find(str)) and
                        (showUnrevealed or discoveredLocations.isDiscovered(name)) then
                    table.insert(res, {
                        text = dt.name,
                        cellId = nil,
                        pos = util.vector2(dt.posX, dt.posY),
                        priority = 100,
                        color = config.data.ui.foundMarkerColor
                    })
                end
            end
        end
    else
        local interiors = {}
        for cellId, list in pairs(entrances) do
            if not cellId:find(commonData.exteriorCellLabel, 1, true) then
                table.insert(interiors, cellId)
                goto continue
            end

            processCell(cellId, true, true)

            ::continue::
        end

        for _, cellId in pairs(interiors) do
            processCell(cellId, false, true)
        end

        local names = mapDataHandler.cellNameData
        for name, dt in pairs(names) do
            local nameLower = stringLib.utf8_lower(name)
            if (nameLower:find(str, 1, true) or usePatternSearch and nameLower:find(str)) and
                    (showUnrevealed or discoveredLocations.isDiscovered(name)) then
                table.insert(res, {
                    text = dt.name,
                    cellId = nil,
                    pos = util.vector2(dt.posX, dt.posY),
                    priority = 1,
                    color = config.data.ui.foundMarkerColor
                })
            end
        end
    end

    return res
end


---@param menu advancedWorldMap.ui.menu.map
local function create(menu)

    local textFilter = ""
    local userInputText = ""

    local showUnrevealed
    if localStorage.data[commonData.showUnrevealedFieldId] ~= nil then
        showUnrevealed = localStorage.data[commonData.showUnrevealedFieldId]
    else
        showUnrevealed = not config.data.legend.onlyDiscovered
    end

    local searchAllLocations = false
    if localStorage.data[commonData.searchAllLocationsFieldId] ~= nil then
        searchAllLocations = localStorage.data[commonData.searchAllLocationsFieldId]
    else
        searchAllLocations = true
    end

    local nearbySearch = localStorage.data[commonData.searchNearbyFieldId]
    if nearbySearch == nil then
        nearbySearch = true
    end

    local searchMode = localStorage.data[commonData.searchModeFieldId] or searchModes.Locations
    if not commonData.isSaveBloatFixed() and searchMode ~= searchModes.Locations then
        searchMode = searchModes.Locations
    end
    localStorage.data[commonData.searchModeFieldId] = searchMode


    local onMapElementCreatedCallback = function (e)
        if textFilter == "" then return end

        if searchMode == searchModes.Locations then
            updateLayoutForMarker(e.marker, textFilter)
        else
            setMarkerColor(e.marker, nil, true)
        end

        if not showUnrevealed then return end
        local handler = e.marker
        local userData = handler:getUserData()
        if not (userData and (userData.type == commonData.doorMarkerType or userData.type == commonData.doorDescrMarkerType)) then
            return
        end

        local cellId = e.mapWidget.cellId
        if cellId == nil and not targetCells[userData.cellId or " "] then return end

        setMarkerVisibility(handler, true)
    end

    local temporaryMarkersData
    ---@type table<string, string[]> by cellId, marker hash
    local temporaryCellMarkerLinks = {}
    local mapInitCallbackFunc = function (e)
        if not temporaryMarkersData then return end

        local cellMarkerHashes = temporaryCellMarkerLinks[e.menu.mapWidget.cellId or commonData.exteriorMapId]
        if not cellMarkerHashes then return end

        for _, hash in pairs(cellMarkerHashes) do
            local dt = temporaryMarkersData[hash]
            if dt then
                createTemporaryMarker(hash, e.menu.mapWidget, e.menu, dt.loc, dt.pos, dt.color, dt.text, dt.destNames, dt.showZoomIn)
            end
        end

        e.menu:update()
    end

    local updateExistingMarkers = function ()
        for _, handler in pairs(menu.mapWidget:getActiveMarkers() or {}) do
            onMapElementCreatedCallback{marker = handler, mapWidget = menu.mapWidget}
        end
    end

    local restoreExistingMarkers = function ()
        for _, handler in pairs(menu.mapWidget:getActiveMarkers() or {}) do
            local userData = handler:getUserData()
            if userData and (userData.type == commonData.doorMarkerType or userData.type == commonData.doorDescrMarkerType) then
                handler:restoreLayout()
            end
        end
    end


    local onMapClosedCallback = function (e)
        resetMarkersVisibility()
    end

    local iconTooltipContent = ui.content{
        {
            type = ui.TYPE.Text,
            props = {
                text = l10n("SearchWidgetTooltip"),
                textColor = config.data.ui.defaultColor,
                textSize = config.data.ui.fontSize,
                autoSize = true,
            }
        }
    }

    local iconLayout = {
        type = ui.TYPE.Image,
        props = {
            resource = searchIcoTexture,
            anchor = util.vector2(0.5, 0.5),
            size = util.vector2(menu.headerHeight - 2, menu.headerHeight - 2),
            color = config.data.ui.defaultColor,
        },
        events = {
            mouseMove = async:callback(function(e, layout)
                tooltip.createOrMove(e, layout, iconTooltipContent, 1)
            end),

            focusLoss = async:callback(function(e, layout)
                tooltip.destroy(layout)
            end),
        }
    }

    ---@param menu advancedWorldMap.ui.menu.map
    local function onOpen(menu, content)
        local mapWidgetSize = menu.mapWidget:getSize()

        eventSys.registerHandler(eventSys.EVENT.onMapElementCreated, onMapElementCreatedCallback)
        eventSys.registerHandler(eventSys.EVENT.onMapClosed, onMapClosedCallback)
        eventSys.registerHandler(eventSys.EVENT.onMapInitialized, mapInitCallbackFunc)

        local size = util.vector2(
            math.max(mapWidgetSize.x / 3, 250),
            mapWidgetSize.y
        )

        local scrollBoxContent = ui.content{}

        local separatorSize = 1
        local searchBarTextEditSize = util.vector2(size.x, math.floor((config.data.ui.fontSize * 1.3 + 1) / 2) * 2)
        local searchBarSize = util.vector2(searchBarTextEditSize.x, searchBarTextEditSize.y + 4)
        local searchTypeSelectorSize = util.vector2(size.x, math.floor(config.data.ui.fontSize * 1.5 / 2) * 2)
        local checkboxesLayoutSize = util.vector2(size.x - config.data.ui.fontSize, math.floor(config.data.ui.fontSize * 1.75 / 2) * 2)
        local scrollBoxSize = util.vector2(size.x, size.y - (searchBarSize.y + checkboxesLayoutSize.y + searchTypeSelectorSize.y + separatorSize + 2))

        local scrollBoxLayout = scrollBox{
            updateFunc = menu.update,
            contentHeight = 0,
            leftOffset = 2,
            size = scrollBoxSize,
            position = util.vector2(0, searchBarSize.y + searchTypeSelectorSize.y + checkboxesLayoutSize.y + separatorSize),
            scrollAmount = config.data.ui.fontSize * 3,
            content = scrollBoxContent,
            autoOptimize = true,
        }

        ---@type advancedWorldMap.ui.scrollBox
        local scrollBoxMeta = scrollBoxLayout.userData.scrollBoxMeta ---@diagnostic disable-line: need-check-nil

        local setSearchResults

        local function fillList(suppressEvent)
            resetMarkersColor()
            removeTemporaryMarkers()
            restoreExistingMarkers()
            searchData = {}
            temporaryMarkersData = {}
            temporaryCellMarkerLinks = {}
            targetCells = {}
            uiUtils.clearContent(scrollBoxContent)
            scrollBoxMeta:setScrollPosition(0)
            scrollBoxMeta:setContentHeight(0)
            scrollBoxMeta:updateContent()

            if textFilter == "" then return end

            if stringLib.length(textFilter) < 2 then
                ui.showMessage(l10n("SearchFilterLengthWarning"))
                return
            end

            scrollBoxContent:add{
                type = ui.TYPE.Text,
                props = {
                    text = l10n("Loading"),
                    textSize = config.data.ui.fontSize,
                    textColor = config.data.ui.defaultColor,
                },
            }
            scrollBoxMeta:updateContent()

            if searchMode == searchModes.Locations then
                updateVisibilityForActiveMarkers(menu.mapWidget, textFilter)
            end

            if searchMode == searchModes.Locations then
                local results = getResults(menu, textFilter, showUnrevealed, searchAllLocations)
                setSearchResults(results, suppressEvent)

            else
                ---@type advancedWorldMap.helpers.search.objectPositions.params
                local params = {
                    text = textFilter,
                    byName = true,
                    inInventory = searchMode == searchModes.Items and config.data.search.inInventory or false,
                    startingCellId = playerRef.cell.id,
                    allowedCells = not showUnrevealed and discoveredLocations.discovered or nil,
                    onlyNearby = nearbySearch,
                    limit = config.data.search.maxObjectResults,
                }

                if searchMode == searchModes.Actors then
                    params.types = {
                        "NPC", "Creature"
                    }
                elseif searchMode == searchModes.Items then
                    params.types = {
                        "Apparatus", "Armor", "Book", "Clothing", "Ingredient", "Light", "Lockpick", "Miscellaneous", "Probe", "Repair", "Weapon"
                    }
                end

                core.sendGlobalEvent("AdvWMap:searchObjects", {
                    player = playerRef,
                    params = params,
                    mode = searchMode,
                })

                menu:update()
            end
        end

        setSearchResults = function (results, suppressEvent)
            if not suppressEvent then
                eventSys.triggerEvent(eventSys.EVENT.onSearch, {results = results, filter = textFilter, mode = searchMode,
                    params = {showUnrevealed = showUnrevealed, searchAllLocations = searchAllLocations, nearbySearch = nearbySearch}})
            end

            for _, res in pairs(results) do
                local dist
                if res.pos then
                    if menu.mapWidget.cellId then
                        if res.cellId == menu.mapWidget.cellId then
                            dist = commonData.distance2D(res.pos, playerRef.position)
                        end
                    else
                        dist = commonData.distance2D(res.pos, playerPos.gexExteriorPos())
                    end
                end
                res.dist = dist or 0
                res.priority = res.priority or 0
            end

            table.sort(results, function (a, b)
                if a.priority ~= b.priority then
                    return a.priority > b.priority
                else
                    return a.dist < b.dist
                end
            end)

            uiUtils.clearContent(scrollBoxContent)

            local height = 0

            for _, dt in ipairs(results) do
                local text = dt.text or ""

                local locations = dt.locations or {
                    {id = dt.cellId, pos = dt.pos}
                }

                local isObjectSearchMode = searchMode ~= searchModes.Locations
                for _, locData in pairs(locations) do
                    if locData.id then
                        targetCells[locData.id] = true
                    end

                    local posHash = getPosHash(locData.id, locData.pos)

                    searchData[posHash] = searchData[posHash] or {}
                    table.insert(searchData[posHash], dt)

                    local function addMarkerData(cellId, pHash, pos, locName, color, tx, showZoomIn)
                        local markerData = temporaryMarkersData[pHash]
                        if not markerData then
                            temporaryMarkersData[pHash] = {
                                posHash = pHash,
                                pos = pos,
                                color = color,
                                text = {[tx] = true},
                                showZoomIn = showZoomIn,
                                loc = locData,
                                destNames = {[locName or ""] = true}
                            }
                            local cellIdForLink = cellId or commonData.exteriorMapId
                            temporaryCellMarkerLinks[cellIdForLink] = temporaryCellMarkerLinks[cellIdForLink] or {}
                            table.insert(temporaryCellMarkerLinks[cellIdForLink], pHash)
                        else
                            if markerData.color ~= color then
                                markerData.color = config.data.ui.foundMarkerColor
                            end
                            if not markerData.text[tx] then
                                markerData.text[tx] = true
                                markerData.destNames[locName] = true
                            end
                        end
                    end

                    local cellName = mapDataHandler.cellNameById[locData.id or cellLib.getCellIdByPos(locData.pos) or ""] or
                        locData.id or string.format("(%d, %d)", math.floor(locData.pos.x), math.floor(locData.pos.y))

                    if locData.id ~= nil then
                        local entrances = getWorldEntrancesForCell(locData.id)
                        for pHash, entranceDt in pairs(entrances) do
                            addMarkerData(nil, pHash, entranceDt.pos, cellName, config.data.ui.foundMarkerLightColor, text, true)
                            targetCells[entranceDt.dCId] = true
                        end
                    end

                    if isObjectSearchMode or locData.id == nil then
                        local color = locData.owner and config.data.ui.foundMarkerLightColor or config.data.ui.foundMarkerColor
                        local markerText = text
                        if locData.owner then
                            local ownerName = locData.owner.name or locData.owner.id or ""
                            markerText = locData.owner.tp == l10n("types.Container") and
                                l10n("SearchMarkerInContainerPattern", {item = text, container = ownerName}) or
                                l10n("SearchMarkerOnActorPattern", {item = text, actor = ownerName})
                        end
                        addMarkerData(locData.id, posHash, locData.pos, cellName, color, markerText, isObjectSearchMode)
                    end
                end

                local tooltipContent = isObjectSearchMode and ui.content {
                    {
                        type = ui.TYPE.Text,
                        props = {
                            text = l10n("ObjectIdTooltipPattern", {id = dt.id or "???"}),
                            textSize = config.data.ui.fontSize,
                            textColor = config.data.ui.defaultColor,
                            autoSize = true,
                        }
                    }
                }

                local textHeight = uiUtils.getTextHeight(text, config.data.ui.fontSize, size.x, config.data.ui.textHeightMul)

                local textLay
                textLay = {
                    type = ui.TYPE.Text,
                    props = {
                        text = text,
                        textSize = config.data.ui.fontSize,
                        textColor = config.data.ui.defaultColor,
                        autoSize = false,
                        size = util.vector2(size.x, textHeight),
                        multiline = true,
                        wordWrap = true,
                        textShadow = true,
                        propagateEvents = false,
                    },
                    userData = {
                        positionIndex = 0,
                    },
                    events = {
                        mousePress = async:callback(function(e, layout)
                            scrollBoxMeta:mousePress(e)
                        end),

                        focusLoss = async:callback(function(e, layout)
                            scrollBoxMeta:focusLoss(e)

                            if layout.props.textShadowColor then
                                layout.props.textShadowColor = nil
                                menu:update()
                            end

                            tooltip.destroy(layout)
                        end),

                        mouseMove = async:callback(function(e, layout)
                            scrollBoxMeta:mouseMove(e)

                            if layout.props.textShadowColor ~= config.data.ui.textShadowColor then
                                layout.props.textShadowColor = config.data.ui.textShadowColor
                                menu:update()
                            end

                            if tooltipContent then
                                tooltip.createOrMove(e, layout, tooltipContent, 1)
                            end
                        end),

                        mouseRelease = async:callback(function(e, layout)
                            if e.button ~= 1 then return end

                            scrollBoxMeta:mouseRelease(e)

                            if scrollBoxMeta.lastMovedDistance < 20 then
                                local index = (layout.userData.positionIndex + 1)
                                if index > #locations then index = 1 end
                                layout.userData.positionIndex = index

                                local locDt = locations[index]
                                if not locDt then return end

                                if menu.mapWidget.cellId ~= locDt.id then
                                    menu:updateMapWidgetCell(locDt.id)
                                end
                                menu.mapWidget:focusOnWorldPosition(locDt.pos)
                                menu.mapWidget:updateMarkers()

                                menu:update()
                            end
                        end),
                    },
                }

                scrollBoxContent:add(textLay)
                scrollBoxContent:add(interval(0, config.data.ui.fontSize))

                height = height + config.data.ui.fontSize + textHeight
            end

            for cellId, hashes in pairs(temporaryCellMarkerLinks) do
                local cachedMapWidget = menu:getCachedMapWidget(cellId)
                if cachedMapWidget then
                    for _, hash in pairs(hashes) do
                        local dt = temporaryMarkersData[hash]
                        if dt then
                            createTemporaryMarker(hash, cachedMapWidget, menu, dt.loc, dt.pos, dt.color, dt.text, dt.destNames, dt.showZoomIn)
                        end
                    end
                end
            end

            updateExistingMarkers()

            scrollBoxMeta:setScrollPosition(0)
            scrollBoxMeta:setContentHeight(height)
            scrollBoxMeta:updateContent()
        end

        local updateCheckboxVisibility

        local searchTypeSelectorButtons = {
            {
                text = l10n("SearchSelectorLocations"),
                checked = searchMode == searchModes.Locations,
                onClick = function (layout)
                    searchMode = searchModes.Locations
                    localStorage.data[commonData.searchModeFieldId] = searchMode
                    updateCheckboxVisibility()
                    fillList()
                end
            },
        }

        if commonData.isSaveBloatFixed() then
            table.insert(searchTypeSelectorButtons, {
                text = l10n("SearchSelectorActors"),
                checked = searchMode == searchModes.Actors,
                onClick = function (layout)
                    searchMode = searchModes.Actors
                    localStorage.data[commonData.searchModeFieldId] = searchMode
                    updateCheckboxVisibility()
                    fillList()
                end
            })
            table.insert(searchTypeSelectorButtons, {
                text = l10n("SearchSelectorItems"),
                checked = searchMode == searchModes.Items,
                onClick = function (layout)
                    searchMode = searchModes.Items
                    localStorage.data[commonData.searchModeFieldId] = searchMode
                    updateCheckboxVisibility()
                    fillList()
                end
            })
        end

        local searchTypeSelectorLayout = selector{
            size = searchTypeSelectorSize,
            anchor = util.vector2(0.5, 0),
            position = util.vector2(size.x / 2, searchBarSize.y),
            update = menu.update,
            buttons = searchTypeSelectorButtons,
        }


        local showUnrevealedCBLayout = checkBox{
            updateFunc = menu.update,
            text = l10n("searchShowUnrevealed"),
            textSize = config.data.ui.fontSize * 0.9,
            anchor = util.vector2(0, 0.5),
            position = util.vector2(0, checkboxesLayoutSize.y / 2),
            checked = showUnrevealed,
            event = function (checked, layout)
                showUnrevealed = checked
                localStorage.data[commonData.showUnrevealedFieldId] = checked
                fillList()
                menu.mapWidget:updateMarkers()
                menu:update()
            end,
            tooltipContent = ui.content {
                {
                    type = ui.TYPE.TextEdit,
                    props = {
                        text = l10n("SearchShowUnrevealedTooltip"),
                        textSize = config.data.ui.fontSize,
                        textColor = config.data.ui.defaultColor,
                        autoSize = true,
                        multiline = true,
                        wordWrap = true,
                        readOnly = true,
                        size = util.vector2(math.max(300, uiUtils.getScaledScreenSize().x / 4), 0),
                    }
                }
            },
        }

        local searchAllLocationsCBLayout = checkBox{
            updateFunc = menu.update,
            text = l10n("searchAllLocationsCheckbox"),
            textSize = config.data.ui.fontSize * 0.9,
            anchor = util.vector2(1, 0.5),
            position = util.vector2(checkboxesLayoutSize.x, checkboxesLayoutSize.y / 2),
            visible = searchMode == searchModes.Locations,
            checked = searchAllLocations,
            event = function (checked, layout)
                searchAllLocations = checked
                localStorage.data[commonData.searchAllLocationsFieldId] = checked
                fillList()
                menu.mapWidget:updateMarkers()
                menu:update()
            end,
            tooltipContent = ui.content {
                {
                    type = ui.TYPE.TextEdit,
                    props = {
                        text = l10n("SearchAllLocationsTooltip"),
                        textSize = config.data.ui.fontSize,
                        textColor = config.data.ui.defaultColor,
                        autoSize = true,
                        multiline = true,
                        wordWrap = true,
                        readOnly = true,
                        size = util.vector2(math.max(300, uiUtils.getScaledScreenSize().x / 4), 0),
                    }
                }
            },
        }

        local searchNearbyCBLayout = checkBox{
            updateFunc = menu.update,
            text = l10n("searchNearbyCheckbox"),
            textSize = config.data.ui.fontSize * 0.9,
            anchor = util.vector2(1, 0.5),
            position = util.vector2(checkboxesLayoutSize.x, checkboxesLayoutSize.y / 2),
            visible = searchMode ~= searchModes.Locations,
            checked = nearbySearch,
            event = function (checked, layout)
                nearbySearch = checked
                localStorage.data[commonData.searchNearbyFieldId] = checked
                fillList()
                menu.mapWidget:updateMarkers()
                menu:update()
            end,
            tooltipContent = ui.content {
                {
                    type = ui.TYPE.TextEdit,
                    props = {
                        text = l10n("searchNearbyTooltip"),
                        textSize = config.data.ui.fontSize,
                        textColor = config.data.ui.defaultColor,
                        autoSize = true,
                        multiline = true,
                        wordWrap = true,
                        readOnly = true,
                        size = util.vector2(math.max(300, uiUtils.getScaledScreenSize().x / 4), 0),
                    }
                }
            },
        }

        updateCheckboxVisibility = function ()
            searchNearbyCBLayout.props.visible = searchMode ~= searchModes.Locations
            searchAllLocationsCBLayout.props.visible = searchMode == searchModes.Locations
        end

        local checkboxesLayout = {
            type = ui.TYPE.Widget,
            props = {
                size = checkboxesLayoutSize,
                anchor = util.vector2(0.5, 0),
                position = util.vector2(size.x / 2, searchBarSize.y + searchTypeSelectorSize.y + separatorSize),
            },
            content = ui.content {
                showUnrevealedCBLayout,
                searchAllLocationsCBLayout,
                searchNearbyCBLayout,
            }
        }

        local searchBarLayout
        searchBarLayout = {
            type = ui.TYPE.Widget,
            props = {
                size = searchBarSize,
            },
            content = ui.content {
                {
                    type = ui.TYPE.TextEdit,
                    props = {
                        text = "",
                        anchor = util.vector2(0, 0.5),
                        size = searchBarTextEditSize,
                        textAlignV = ui.ALIGNMENT.Center,
                        textSize = config.data.ui.fontSize,
                        position = util.vector2(2, searchBarTextEditSize.y / 2 + 2),
                        textColor = config.data.ui.defaultColor,
                    },
                    events = {
                        textChanged = async:callback(function(text, layout)
                            userInputText = text
                            textFilter = stringLib.utf8_lower(text)
                            usePatternSearch = stringLib.hasEscapeCharacters(text)
                            searchBarLayout.content[1].props.text = userInputText
                        end),
                        keyRelease = async:callback(function(e, layout)
                            if e.code == input.KEY.Enter then
                                searchBarLayout.content[1].props.text = userInputText
                                fillList()
                                menu.mapWidget:updateMarkers()
                                menu:update()
                            end
                        end),
                        focusLoss = async:callback(function(layout)
                            searchBarLayout.content[1].props.text = userInputText
                        end),
                    }
                },
                button{
                    updateFunc = menu.update,
                    text = l10n("Search"),
                    size = util.vector2(100, config.data.ui.fontSize * 0.9),
                    textSize = config.data.ui.fontSize * 0.9,
                    anchor = util.vector2(1, 0.5),
                    position = util.vector2(size.x - 2, searchBarTextEditSize.y / 2 + 2),
                    tooltipDelay = 0.75,
                    tooltipContent = ui.content {
                        {
                            type = ui.TYPE.TextEdit,
                            props = {
                                text = l10n("SearchBtnPatternMatchingInfo"),
                                textSize = config.data.ui.fontSize,
                                textColor = config.data.ui.defaultColor,
                                autoSize = true,
                                multiline = true,
                                wordWrap = true,
                                readOnly = true,
                                size = util.vector2(math.max(300, uiUtils.getScaledScreenSize().x / 4), 0),
                            }
                        }
                    },
                    event = function (layout)
                        fillList()
                        menu.mapWidget:updateMarkers()
                        menu:update()
                    end
                },
                borders()
            }
        }


        local windowLayout = {
            type = ui.TYPE.Widget,
            props = {
                size = size,
            },
            userData = {

            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        relativeSize = util.vector2(1, 1),
                        color = config.data.ui.backgroundColor,
                        resource = uiUtils.whiteTexture,
                    },
                },
                searchBarLayout,
                searchTypeSelectorLayout,
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture{ path = "textures/menu_thin_border_top.dds" },
                        tileH = true,
                        tileV = false,
                        size = util.vector2(0, separatorSize),
                        relativeSize = util.vector2(separatorSize, 0),
                        position = util.vector2(0, searchBarSize.y + searchTypeSelectorSize.y),
                    },
                },
                checkboxesLayout,
                scrollBoxLayout,
                borders()
            }
        }


        iconLayout.props.color = config.data.ui.whiteColor

        content:add(windowLayout)

        menu.userData.advWMapSearch = function (text, params)
            params = params or {}
            if params.showUnrevealed ~= nil then
                showUnrevealedCBLayout.userData.meta:setChecked(params.showUnrevealed)
            end
            if params.searchAllLocations ~= nil then
                searchAllLocationsCBLayout.userData.meta:setChecked(params.showUnrevealed)
            end
            searchBarLayout.content[1].events.textChanged(text)

            fillList()
        end

        menu.userData.advWMapSetSearchResults = setSearchResults
    end

    local function onClose(menu)
        textFilter = ""
        usePatternSearch = false
        userInputText = ""
        menu.userData.advWMapSearch = nil
        menu.userData.advWMapSetSearchResults = nil
        iconLayout.props.color = config.data.ui.defaultColor
        resetMarkersVisibility()
        resetMarkersColor()
        removeTemporaryMarkers()
        searchData = {}
        temporaryMarkersData = nil
        temporaryCellMarkerLinks = {}
        targetCells = {}
        eventSys.unregisterHandler(eventSys.EVENT.onMapElementCreated, onMapElementCreatedCallback)
        eventSys.unregisterHandler(eventSys.EVENT.onMapClosed, onMapClosedCallback)
        eventSys.unregisterHandler(eventSys.EVENT.onMapInitialized, mapInitCallbackFunc)
    end

    menu:addWidget{
        id = "AdvancedWorldMap:Search",
        layout = iconLayout,
        priority = 9800,
        onOpen = onOpen,
        onClose = onClose,
    }
end


eventSys.registerHandler(eventSys.EVENT["onMenuOpened"], function (e)
    create(e.menu)
end, 9800)
