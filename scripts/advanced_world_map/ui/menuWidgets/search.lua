local async = require("openmw.async")
local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")
local input = require('openmw.input')

local commonData = require("scripts.advanced_world_map.common")
local config = require("scripts.advanced_world_map.config.configLib")

local uiUtils = require("scripts.advanced_world_map.ui.utils")
local stringLib = require("scripts.advanced_world_map.utils.string")

local localStorage = require("scripts.advanced_world_map.storage.localStorage")
local dynamicDataHandler = require("scripts.advanced_world_map.dynamicDataHandler")
local playerPos = require("scripts.advanced_world_map.playerPosition")

local eventSys = require("scripts.advanced_world_map.eventSys")

local scrollBox = require("scripts.advanced_world_map.ui.scrollBox")
local borders = require("scripts.advanced_world_map.ui.borders")
local button = require("scripts.advanced_world_map.ui.button")
local interval = require('scripts.advanced_world_map.ui.interval')
local checkBox = require("scripts.advanced_world_map.ui.checkBox")

local l10n = core.l10n(commonData.l10nKey)


local searchIcoTexture = ui.texture{ path = commonData.searchWidgetIcon }


---@return table<string, string> res by cell id - cell name
local function getAvailableCellNamesFromInterior(cellId, checked, res)
    checked = checked or {}
    res = res or {}

    if checked[cellId] then return res end

    for destId, destDt in pairs(dynamicDataHandler.cellDirections[cellId] or {}) do
        if not checked[destId] then
            checked[destId] = true
            if not destDt.isEx then
                res[destId] = destDt.name
                getAvailableCellNamesFromInterior(destId, checked, res)
            end
        end
    end

    return res
end


---@param menu advancedWorldMap.ui.menu.map
---@return {id : string, layerId : integer, name : string, pos : {x : number, y : number}, dist : number?, parent : string?, priority : number}[]
local function getResults(menu, str, hideUnrevealed, inAllInteriors)
    str = stringLib.utf8_lower(str)

    local res = {}

    local addedHashset = {}

    local function add(params, priority)

        if inAllInteriors and params.userData and params.userData.cellId then

            for cellId, cellName in pairs(getAvailableCellNamesFromInterior(params.userData.cellId)) do

                if cellId ~= params.userData.cellId and stringLib.utf8_lower(cellName):find(str) then
                    local parentName = params.searchLabel or params.text or params.searchText

                    table.insert(res, {id = params.id, layerId = params.layerId, parent = parentName,
                        name = cellName, pos = params.pos, priority = priority or 0})
                end

            end

        end

        if params.searchText:find(str) then
            table.insert(res, {id = params.id, layerId = params.layerId, priority = priority or 0,
                name = params.searchLabel or params.text or params.searchText, pos = params.pos})
        end
    end

    for i, content in ipairs({
                menu.mapWidget:getLayerLayout(menu.mapWidget.layerIds.region).content,
                menu.mapWidget:getLayerLayout(menu.mapWidget.layerIds.map).content,
                menu.mapWidget:getLayerLayout(menu.mapWidget.layerIds.marker).content,
                menu.mapWidget:getLayerLayout(menu.mapWidget.layerIds.nonInteractive).content,
            }) do
        for _, marker in ipairs(content) do
            if not marker.userData or not marker.userData.params then goto continue end

            ---@type advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params|advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params
            local params = marker.userData.params

            if not params.searchText or not params.pos or not params.searchText:find(str)
                or params.showWhenZoomedIn or params.showWhenZoomedOut
                or hideUnrevealed and params.visible == false then goto continue end

            addedHashset[params] = true
            add(params, i)

            ::continue::
        end
    end

    for _, tb in pairs({menu.mapWidget.zoomOutMarkers, menu.mapWidget.zoomInMarkers}) do
        for _, cellData in pairs(tb) do
            for _, dt in pairs(cellData) do
                if not dt.params.searchText or not dt.params.pos or hideUnrevealed and dt.params.visible == false
                        or addedHashset[dt.params] then goto continue end

                add(dt.params, dt.params.showWhenZoomedOut and 2 or dt.params.showWhenZoomedIn and 3 or 4)

                ::continue::
            end
        end
    end

    return res
end


---@param menu advancedWorldMap.ui.menu.map
local function create(menu)

    local iconLayout = {
        type = ui.TYPE.Image,
        props = {
            resource = searchIcoTexture,
            anchor = util.vector2(0.5, 0.5),
            size = util.vector2(menu.headerHeight - 2, menu.headerHeight - 2),
            color = config.data.ui.defaultColor,
        }
    }

    local mapWidgetSize = menu.mapWidget:getSize()

    local size = util.vector2(
        math.max(mapWidgetSize.x / 3, 250),
        mapWidgetSize.y
    )

    local scrollBoxContent = ui.content{}

    local scrollBoxSize = util.vector2(size.x, size.y - config.data.ui.fontSize * 5 - 6)

    local scrollBoxLayout = scrollBox{
        updateFunc = menu.update,
        contentHeight = 0,
        leftOffset = 2,
        size = scrollBoxSize,
        position = util.vector2(0, config.data.ui.fontSize * 5 + 4),
        scrollAmount = config.data.ui.fontSize * 2,
        content = scrollBoxContent,
    }

    ---@type advancedWorldMap.ui.scrollBox
    local scrollBoxMeta = scrollBoxLayout.userData.scrollBoxMeta ---@diagnostic disable-line: need-check-nil

    local textFilter = ""

    local function fill(sortByDistance, hideUnrevealed, searchInInteriors)
        uiUtils.clearContent(scrollBoxContent)

        if textFilter == "" then return end

        local results = getResults(menu, textFilter, hideUnrevealed, searchInInteriors)

        if sortByDistance then ---@diagnostic disable-line: need-check-nil
            for _, res in pairs(results) do
                res.dist = commonData.distance2D(res.pos, playerPos.gexExteriorPos())
            end

            table.sort(results, function (a, b)
                return a.dist < b.dist
            end)
        else
            table.sort(results, function (a, b)
                return a.priority < b.priority
            end)
        end

        local height = 0

        for _, dt in ipairs(results) do
            local text
            if dt.parent and dt.parent ~= dt.name then
                text = string.format("%s\n(%s %s)\n(%d, %d)", dt.name, l10n("from"), dt.parent, dt.pos.x, dt.pos.y)
            else
                text = string.format("%s\n(%d, %d)", dt.name, dt.pos.x, dt.pos.y)
            end

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
                            menu.mapWidget:focusOnWorldPosition(dt.pos)
                            menu.mapWidget:setZoom(math.max(8, menu.mapWidget.zoom))
                            menu.mapWidget:forceChangeMarker(dt.id, dt.layerId, {
                                visible = true,
                                size = menu.mapWidget.scaleFunctions.marker(util.vector2(14, 14), menu.mapWidget.zoom),
                                color = config.data.ui.selectionColor
                            })
                        end
                    end),
                },
            }

            scrollBoxContent:add(textLay)
            scrollBoxContent:add(interval(0, config.data.ui.fontSize))

            height = height + config.data.ui.fontSize + textHeight
        end

        scrollBoxMeta:setScrollPosition(0)
        scrollBoxMeta:setContentHeight(height)
    end

    local sortByDistance = localStorage.data[commonData.sortByDistanceFieldId] ~= nil and localStorage.data[commonData.sortByDistanceFieldId] or false

    local hideUnrevealed
    if localStorage.data[commonData.hideUnrevealedFieldId] ~= nil then
        hideUnrevealed = localStorage.data[commonData.hideUnrevealedFieldId]
    else
        hideUnrevealed = config.data.legend.onlyDiscovered
    end

    local searchInInteriors = false
    if localStorage.data[commonData.searchInInteriorsFieldId] ~= nil then
        searchInInteriors = localStorage.data[commonData.searchInInteriorsFieldId]
    else
        searchInInteriors = true
    end

    local sortByDistanceCBLayout = checkBox{
        updateFunc = menu.update,
        text = l10n("sortByDistance"),
        textSize = config.data.ui.fontSize * 0.9,
        position = util.vector2(2, config.data.ui.fontSize + 9),
        checked = sortByDistance,
        event = function (checked, layout)
            sortByDistance = checked
            localStorage.data[commonData.sortByDistanceFieldId] = checked
            fill(sortByDistance, hideUnrevealed, searchInInteriors)
        end
    }

    local hideUnrevealedCBLayout = checkBox{
        updateFunc = menu.update,
        text = l10n("hideUnrevealed"),
        textSize = config.data.ui.fontSize * 0.9,
        position = util.vector2(2, config.data.ui.fontSize * 2 + 12),
        checked = hideUnrevealed,
        event = function (checked, layout)
            hideUnrevealed = checked
            localStorage.data[commonData.hideUnrevealedFieldId] = checked
            fill(sortByDistance, hideUnrevealed, searchInInteriors)
        end
    }

        local searchInInteriorsCBLayout = checkBox{
        updateFunc = menu.update,
        text = l10n("searchInAllInteriors"),
        textSize = config.data.ui.fontSize * 0.9,
        position = util.vector2(2, config.data.ui.fontSize * 3 + 15),
        checked = searchInInteriors,
        event = function (checked, layout)
            searchInInteriors = checked
            localStorage.data[commonData.searchInInteriorsFieldId] = checked
            fill(sortByDistance, hideUnrevealed, searchInInteriors)
        end
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
                        textFilter = text
                    end),
                    keyRelease = async:callback(function(e, layout)
                        if e.code == input.KEY.Enter then
                            searchBarLayout.content[1].props.text = textFilter
                            fill(sortByDistance, hideUnrevealed, searchInInteriors)
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
                    fill(sortByDistance, hideUnrevealed, searchInInteriors)
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
            sortByDistanceCBLayout,
            hideUnrevealedCBLayout,
            searchInInteriorsCBLayout,
            searchBarLayout,
            scrollBoxLayout,
            borders()
        }
    }

    local function onOpen(content)
        iconLayout.props.color = config.data.ui.defaultLightColor

        content:add(windowLayout)
    end

    local function onClose()
        iconLayout.props.color = config.data.ui.defaultColor
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
end, math.huge)
