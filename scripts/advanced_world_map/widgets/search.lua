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

local localStorage = require("scripts.advanced_world_map.storage.localStorage")
local dynamicDataHandler = require("scripts.advanced_world_map.dynamicDataHandler")
local playerPos = require("scripts.advanced_world_map.playerPosition")
local discoveredLocations = require("scripts.advanced_world_map.discoveredLocations")

local eventSys = require("scripts.advanced_world_map.eventSys")

local scrollBox = require("scripts.advanced_world_map.ui.scrollBox")
local borders = require("scripts.advanced_world_map.ui.borders")
local button = require("scripts.advanced_world_map.ui.button")
local interval = require('scripts.advanced_world_map.ui.interval')
local checkBox = require("scripts.advanced_world_map.ui.checkBox")

local l10n = core.l10n(commonData.l10nKey)

local defaultColor = util.color.rgb(0, 0, 0)

local searchIcoTexture = ui.texture{ path = commonData.searchWidgetIcon }

local worldMarkerTexture = ui.texture{ path = commonData.searchWorldMarkerPath }


---@type table<string, advancedWorldMap.ui.mapElementMeta>
local hiddenMarkers = {}
---@type table<string, advancedWorldMap.ui.mapElementMeta>
local modifiedMarkers = {}
---@type table<any, advancedWorldMap.ui.mapElementMeta>
local temporaryMarkers = {}
---@type table<string, any[]> by pos hash
local searchData = {}
---@type table<string, boolean>
local targetCells = {}


---@param handler advancedWorldMap.ui.mapElementMeta
local function getMarkerId(handler)
    return tostring(handler._parent.cellId).."_"..handler:getId()
end


---@return string
local function getPosHash(cellId, pos)
    return string.format("pos_%s_%d_%d", tostring(cellId), pos.x, pos.y)
end


---@param mapWidget advancedWorldMap.ui.mapWidgetMeta
local function createTemporaryMarker(id, mapWidget, pos, color, text)
    if temporaryMarkers[id] then return end

    local h = mapWidget:createImageMarker{
        layerId = mapWidget.layerIds.marker,
        pos = pos,
        color = color or config.data.ui.selectionColor,
        texture = worldMarkerTexture,
        anchor = util.vector2(0.5, 1),
        size = util.vector2(config.data.legend.markerSize * 2.5, config.data.legend.markerSize * 5),
        showWhenZoomedOut = true,
        tooltipContent = text and ui.content{
            {
                type = ui.TYPE.TextEdit,
                props = {
                    text = text,
                    textSize = config.data.ui.fontSize,
                    textColor = config.data.ui.defaultColor,
                    autoSize = true,
                    multiline = true,
                    wordWrap = true,
                    readOnly = true,
                    size = util.vector2(math.max(300, uiUtils.getScaledScreenSize().x / 4), 0),
                    textAlignH = ui.ALIGNMENT.Center,
                }
            }
        } or nil,
    }
    temporaryMarkers[id] = h
end


local function removeTemporaryWorldMarkers()
    for i, handler in pairs(temporaryMarkers) do
        handler:destroy()
        temporaryMarkers[i] = nil
    end
end


---@param handler advancedWorldMap.ui.mapElementMeta
local function setMarkerVisibility(handler, val)
    if val then
        handler:updateLayout{ ---@diagnostic disable-line: missing-fields
            visible = (handler._params.visible == true or handler._params.visible == nil) and true or false,
        }
        hiddenMarkers[getMarkerId(handler)] = nil
        local userData = handler:getUserData()
        if userData and (userData.type == commonData.doorMarkerType or userData.type == commonData.doorDescrMarkerType) then
            userData.filtered = nil
        end
    else
        handler:updateLayout{visible = false} ---@diagnostic disable-line: missing-fields
        hiddenMarkers[getMarkerId(handler)] = handler
        local userData = handler:getUserData()
        if userData and (userData.type == commonData.doorMarkerType or userData.type == commonData.doorDescrMarkerType) then
            userData.filtered = true
        end
    end
end

local function resetMarkersVisibility()
    for i, handler in pairs(hiddenMarkers) do
        setMarkerVisibility(handler, true)
        hiddenMarkers[i] = nil
    end
end

---@param handler advancedWorldMap.ui.mapElementMeta
local function setMarkerColor(handler, color, reset)
    if not color and not reset then return end

    if reset then
        handler:updateLayout{ ---@diagnostic disable-line: missing-fields
            color = handler._params.color or defaultColor,
            alpha = handler._params.alpha or 1,
        }
        modifiedMarkers[getMarkerId(handler)] = nil
    else
        handler:updateLayout{ ---@diagnostic disable-line: missing-fields
            color = color,
            alpha = 1,
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
local function updateLayoutForMarker(handler, textFilter, color)
    local userData = handler:getUserData()
    if not userData then return end

    local changeVisibility = false

    if userData.allowSearchFilter then
        local posHash = getPosHash(handler._parent.cellId, handler._params.pos)
        local data = searchData[posHash]

        if data and next(data) then
            local params = data[1]
            setMarkerColor(handler, params.color)
        elseif userData.searchText and userData.searchText:find(textFilter) then
            setMarkerColor(handler, color or config.data.ui.selectionColor)
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

    for _, destDt in pairs(dynamicDataHandler.entrances[cellId] or {}) do
        if not checked[destDt.destCellId] then
            checked[destDt.destCellId] = true
            if not destDt.isDestEx then
                res[destDt.destCellId] = destDt.name
                getAvailableInteriorNamesFromInterior(destDt.destCellId, checked, res)
            end
        end
    end

    return res
end


---@return table<string, string> res by cell id - cell name
local function getAvailableExteriorNamesFromInterior(cellId, checked, res)
    checked = checked or {}
    res = res or {}

    if checked[cellId] then return res end

    for _, destDt in pairs(dynamicDataHandler.entrances[cellId] or {}) do
        if not checked[destDt.destCellId] then
            checked[destDt.destCellId] = true
            if destDt.isDestEx then
                res[destDt.destCellId] = destDt.name
            else
                getAvailableExteriorNamesFromInterior(destDt.destCellId, checked, res)
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
    for exCellId, _ in pairs(exteriorCells) do
        for _, dt in pairs(dynamicDataHandler.entrances[exCellId] or {}) do
            res[getPosHash(nil, dt.pos)] = dt
        end
    end

    return res
end


---@param menu advancedWorldMap.ui.menu.map
---@return {cellId : string?, pos : {x : number, y : number}, text : string, color : any, dist : number?, priority : number?, worldMarker : {pos : {x : number, y : number}, color : any}?}[]
local function getResults(menu, str, hideUnrevealed, searchAllLocations)
    local res = {}

    local mapWidget = menu.mapWidget

    local entrances = dynamicDataHandler.entrances or {}

    local checked = {}
    local function processCell(cellId, isExterior, inInteriors)
        if checked[cellId] then return end
        checked[cellId] = true

        if isExterior == nil then isExterior = cellId:find(commonData.exteriorCellLabel) and true or false end

        local name = dynamicDataHandler.cellNameById[cellId] or string.format("%s: \"%s\"", l10n("CellId"), cellId)
        local nameLower = stringLib.utf8_lower(name)

        if not isExterior and nameLower:find(str) and (not hideUnrevealed or discoveredLocations.isDiscovered(cellId)) then
            local doors = dynamicDataHandler.entrances[cellId]
            local pos = {x = 0, y = 0}
            if doors then
                local cnt = #doors
                for _, d in pairs(doors) do
                    pos.x = pos.x + d.pos.x
                    pos.y = pos.y + d.pos.y
                end
                pos.x = pos.x / cnt
                pos.y = pos.y / cnt
            end

            table.insert(res, {
                text = name,
                cellId = cellId,
                pos = pos,
                priority = 0,
                color = config.data.ui.selectionColor
            })
        end

        if inInteriors then
            if isExterior then
                for _, dt in pairs(dynamicDataHandler.entrances[cellId] or {}) do
                    if checked[dt.destCellId] then goto continue end
                    checked[dt.destCellId] = true

                    local destNameLower = stringLib.utf8_lower(dt.name)
                    if destNameLower:find(str) and (not hideUnrevealed or discoveredLocations.isDiscovered(dt.destCellId)) then
                        table.insert(res, {
                            text = dt.fullName,
                            cellId = not dt.isExterior and dt.cellId or nil,
                            pos = dt.pos,
                            priority = 0,
                            color = config.data.ui.selectionColor
                        })
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
                if not cellId:find(commonData.exteriorCellLabel) then
                    goto continue
                end

                processCell(cellId, true, true)

                ::continue::
            end

            local names = dynamicDataHandler.cellNameData
            for name, dt in pairs(names) do
                if stringLib.utf8_lower(name):find(str) and (not hideUnrevealed or discoveredLocations.isDiscovered(name)) then
                    table.insert(res, {
                        text = string.format("%s\n(%d, %d)", dt.name, dt.posX, dt.posY),
                        cellId = nil,
                        pos = util.vector2(dt.posX, dt.posY),
                        priority = 100,
                        color = config.data.ui.selectionColor
                    })
                end
            end
        end
    else
        local interiors = {}
        for cellId, list in pairs(entrances) do
            if not cellId:find(commonData.exteriorCellLabel) then
                table.insert(interiors, cellId)
                goto continue
            end

            processCell(cellId, true, true)

            ::continue::
        end

        for _, cellId in pairs(interiors) do
            processCell(cellId, false, true)
        end

        local names = dynamicDataHandler.cellNameData
        for name, dt in pairs(names) do
            if stringLib.utf8_lower(name):find(str) and (not hideUnrevealed or discoveredLocations.isDiscovered(name)) then
                table.insert(res, {
                    text = string.format("%s\n(%d, %d)", dt.name, dt.posX, dt.posY),
                    cellId = nil,
                    pos = util.vector2(dt.posX, dt.posY),
                    priority = 1,
                    color = config.data.ui.selectionColor
                })
            end
        end
    end

    return res
end


---@param menu advancedWorldMap.ui.menu.map
local function create(menu)

    local textFilter = ""

    local onMapElementCreatedCallback = function (e)
        if textFilter == "" then return end

        updateLayoutForMarker(e.marker, textFilter)
    end

    local worldMarkersData
    local mapInitCallbackFunc = function (e)
        if not worldMarkersData or e.cellId ~= nil then return end

        for _, dt in pairs(worldMarkersData) do
            createTemporaryMarker(dt.posHash, e.mapWidget, dt.pos, dt.color, dt.text)
        end
        e.menu:update()
    end


    local iconLayout = {
        type = ui.TYPE.Image,
        props = {
            resource = searchIcoTexture,
            anchor = util.vector2(0.5, 0.5),
            size = util.vector2(menu.headerHeight - 2, menu.headerHeight - 2),
            color = config.data.ui.defaultColor,
        }
    }

    local function onOpen(content)
        local mapWidgetSize = menu.mapWidget:getSize()

        eventSys.registerHandler(eventSys.events.onMapElementCreated, onMapElementCreatedCallback)

        local size = util.vector2(
            math.max(mapWidgetSize.x / 3, 250),
            mapWidgetSize.y
        )

        local scrollBoxContent = ui.content{}

        local scrollBoxSize = util.vector2(size.x, size.y - (config.data.ui.fontSize * 4 + 4))

        local scrollBoxLayout = scrollBox{
            updateFunc = menu.update,
            contentHeight = 0,
            leftOffset = 2,
            size = scrollBoxSize,
            position = util.vector2(0, config.data.ui.fontSize * 4 + 4),
            scrollAmount = config.data.ui.fontSize * 2,
            content = scrollBoxContent,
        }

        ---@type advancedWorldMap.ui.scrollBox
        local scrollBoxMeta = scrollBoxLayout.userData.scrollBoxMeta ---@diagnostic disable-line: need-check-nil

        local function fill(hideUnrevealed, searchAllLocations)
            resetMarkersVisibility()
            resetMarkersColor()
            removeTemporaryWorldMarkers()
            searchData = {}
            worldMarkersData = {}
            targetCells = {}
            uiUtils.clearContent(scrollBoxContent)

            if textFilter == "" then return end

            updateVisibilityForActiveMarkers(menu.mapWidget, textFilter)

            local results = getResults(menu, textFilter, hideUnrevealed, searchAllLocations)

            eventSys.triggerEvent(eventSys.events.onSearch, {results = results, filter = textFilter,
                params = {hideUnrevealed = hideUnrevealed, searchAllLocations = searchAllLocations}})

            for _, res in pairs(results) do
                local dist
                if menu.mapWidget.cellId then
                    if res.cellId == menu.mapWidget.cellId then
                        dist = commonData.distance2D(res.pos, playerRef.position)
                    end
                else
                    dist = commonData.distance2D(res.pos, playerPos.gexExteriorPos())
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

            local height = 0

            for _, dt in ipairs(results) do
                local text = dt.text or ""

                if dt.cellId then
                    targetCells[dt.cellId] = true
                end

                local posHash = getPosHash(dt.cellId, dt.pos)
                local worldMarkerPosHash = dt.worldMarker and dt.worldMarker.pos and getPosHash(nil, dt.worldMarker.pos) or nil

                searchData[posHash] = searchData[posHash] or {}
                table.insert(searchData[posHash], dt)
                if worldMarkerPosHash then
                    searchData[worldMarkerPosHash] = searchData[worldMarkerPosHash] or {}
                    table.insert(searchData[worldMarkerPosHash], dt.worldMarker)
                end

                local function addWorldMarkerData(pHash, pos, color, tx)
                    if not worldMarkersData[pHash] then
                        worldMarkersData[pHash] = {
                            posHash = pHash,
                            pos = pos,
                            color = color,
                            text = tx,
                        }
                    elseif worldMarkersData[pHash].color ~= color then
                        worldMarkersData[pHash].color = config.data.ui.selectionColor
                    end
                end

                if dt.cellId == nil then
                    addWorldMarkerData(posHash, dt.pos, config.data.ui.selectionColor, text)
                else
                    local entrances = getWorldEntrancesForCell(dt.cellId)
                    for pHash, entranceDt in pairs(entrances) do
                        addWorldMarkerData(pHash, entranceDt.pos, config.data.ui.selectionLightColor, text)
                    end
                end
                -- elseif dt.worldMarker and dt.worldMarker.pos then
                --     table.insert(worldMarkersData, {
                --         posHash = worldMarkerPosHash,
                --         pos = dt.worldMarker.pos,
                --         color = config.data.ui.selectionLightColor,
                --         text = text,
                --     })
                -- end

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
                        textShadowColor = config.data.ui.shadowColor,
                        propagateEvents = false,
                    },
                    userData = {
                        shadowColor = config.data.ui.shadowColor,
                    },
                    events = {
                        mousePress = async:callback(function(e, layout)
                            scrollBoxMeta:mousePress(e)
                        end),

                        focusLoss = async:callback(function(e, layout)
                            scrollBoxMeta:focusLoss(e)

                            if layout.userData.shadowColor ~= config.data.ui.shadowColor then
                                textLay.props.textShadowColor = config.data.ui.shadowColor
                                layout.userData.shadowColor = config.data.ui.shadowColor
                                menu:update()
                            end
                        end),

                        mouseMove = async:callback(function(e, layout)
                            scrollBoxMeta:mouseMove(e)

                            if layout.userData.shadowColor ~= config.data.ui.selectionColor then
                                textLay.props.textShadowColor = config.data.ui.selectionColor
                                layout.userData.shadowColor = config.data.ui.selectionColor
                                menu:update()
                            end
                        end),

                        mouseRelease = async:callback(function(e, layout)
                            if e.button ~= 1 then return end

                            scrollBoxMeta:mouseRelease(e)

                            if scrollBoxMeta.lastMovedDistance < 20 then
                                if menu.mapWidget.cellId ~= dt.cellId then
                                    menu:updateMapWidgetCell(dt.cellId)
                                end
                                menu.mapWidget:focusOnWorldPosition(dt.pos)
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

            local worldMapWidget = menu:getCachedMapWidget()
            if worldMapWidget then
                for posHash, dt in pairs(worldMarkersData) do
                    createTemporaryMarker(posHash, worldMapWidget, dt.pos, dt.color, dt.text)
                end
            else
                eventSys.registerHandler(eventSys.events.onMapInitialized, mapInitCallbackFunc)
            end

            scrollBoxMeta:setScrollPosition(0)
            scrollBoxMeta:setContentHeight(height)
        end


        local hideUnrevealed
        if localStorage.data[commonData.hideUnrevealedFieldId] ~= nil then
            hideUnrevealed = localStorage.data[commonData.hideUnrevealedFieldId]
        else
            hideUnrevealed = config.data.legend.onlyDiscovered
        end

        local searchAllLocations = false
        if localStorage.data[commonData.searchAllLocationsFieldId] ~= nil then
            searchAllLocations = localStorage.data[commonData.searchAllLocationsFieldId]
        else
            searchAllLocations = true
        end

        local hideUnrevealedCBLayout = checkBox{
            updateFunc = menu.update,
            text = l10n("searchHideUnrevealed"),
            textSize = config.data.ui.fontSize * 0.9,
            position = util.vector2(2, config.data.ui.fontSize + 9),
            checked = hideUnrevealed,
            event = function (checked, layout)
                hideUnrevealed = checked
                localStorage.data[commonData.hideUnrevealedFieldId] = checked
                fill(hideUnrevealed, searchAllLocations)
            end,
            tooltipContent = ui.content {
                {
                    type = ui.TYPE.TextEdit,
                    props = {
                        text = l10n("SearchHideUnrevealedTooltip"),
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
            position = util.vector2(2, config.data.ui.fontSize * 2 + 12),
            checked = searchAllLocations,
            event = function (checked, layout)
                searchAllLocations = checked
                localStorage.data[commonData.searchAllLocationsFieldId] = checked
                fill(hideUnrevealed, searchAllLocations)
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

        local searchBarLayout
        searchBarLayout = {
            type = ui.TYPE.Widget,
            props = {
                size = util.vector2(size.x, config.data.ui.fontSize + 4),
            },
            content = ui.content {
                {
                    type = ui.TYPE.TextEdit,
                    props = {
                        text = "",
                        anchor = util.vector2(0, 0.5),
                        size = util.vector2(size.x - 114, config.data.ui.fontSize),
                        textAlignV = ui.ALIGNMENT.Center,
                        textSize = config.data.ui.fontSize,
                        position = util.vector2(2, config.data.ui.fontSize / 2 + 2),
                        textColor = config.data.ui.defaultColor,
                    },
                    events = {
                        textChanged = async:callback(function(text, layout)
                            textFilter = stringLib.utf8_lower(text)
                        end),
                        keyRelease = async:callback(function(e, layout)
                            if e.code == input.KEY.Enter then
                                searchBarLayout.content[1].props.text = textFilter
                                fill(hideUnrevealed, searchAllLocations)
                                menu.mapWidget:updateMarkers()
                                menu:update()
                            end
                        end),
                        focusLoss = async:callback(function(layout)
                            searchBarLayout.content[1].props.text = textFilter
                        end),
                    }
                },
                button{
                    updateFunc = menu.update,
                    text = l10n("Search"),
                    size = util.vector2(100, config.data.ui.fontSize * 0.9),
                    textSize = config.data.ui.fontSize * 0.9,
                    anchor = util.vector2(1, 0.5),
                    position = util.vector2(size.x - 2, config.data.ui.fontSize / 2 + 2),
                    event = function (layout)
                        fill(hideUnrevealed, searchAllLocations)
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
                color = config.data.ui.defaultColor,
            },
            userData = {

            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        relativeSize = util.vector2(1, 1),
                        color = config.data.ui.backgroundColor,
                        alpha = math.max(config.data.ui.headerBackgroundAlpha / 100, 0.25),
                        resource = uiUtils.whiteTexture,
                    },
                },
                hideUnrevealedCBLayout,
                searchAllLocationsCBLayout,
                searchBarLayout,
                scrollBoxLayout,
                borders()
            }
        }


        iconLayout.props.color = config.data.ui.defaultLightColor

        content:add(windowLayout)
    end

    local function onClose()
        iconLayout.props.color = config.data.ui.defaultColor
        resetMarkersVisibility()
        resetMarkersColor()
        removeTemporaryWorldMarkers()
        searchData = {}
        worldMarkersData = {}
        targetCells = {}
        eventSys.unregisterHandler(eventSys.events.onMapElementCreated, onMapElementCreatedCallback)
    end

    menu:addWidget{
        id = "AdvancedWorldMap:Search",
        layout = iconLayout,
        onOpen = onOpen,
        onClose = onClose,
    }
end


eventSys.registerHandler(eventSys.events["onMenuOpened"], function (e)
    create(e.menu)
end, 99998)
