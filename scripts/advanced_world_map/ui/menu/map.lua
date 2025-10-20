local async = require("openmw.async")
local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")
local playerRef = require("openmw.self")
local types = require("openmw.types")

local customTemplates = require("scripts.advanced_world_map.ui.templates")

local commonData = require("scripts.advanced_world_map.common")
local config = require("scripts.advanced_world_map.config.configLib")

local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local mathlib = require("scripts.advanced_world_map.utils.math")
local cellLib = require("scripts.advanced_world_map.utils.cell")
local uiUtils = require("scripts.advanced_world_map.ui.utils")
local log = require("scripts.advanced_world_map.utils.log")

local dataHandler = require("scripts.advanced_world_map.mapDataHandler")
local dynamicDataHandler = require("scripts.advanced_world_map.dynamicDataHandler")

local discoveredLocs = require("scripts.advanced_world_map.discoveredLocations")
local disabledDoors = require("scripts.advanced_world_map.disabledDoors")

local eventSys = require("scripts.advanced_world_map.eventSys")

local l10n = core.l10n(commonData.l10nKey)

local button = require("scripts.advanced_world_map.ui.button")
local scrollBox = require("scripts.advanced_world_map.ui.scrollBox")
local interval = require("scripts.advanced_world_map.ui.interval")
local checkBox = require("scripts.advanced_world_map.ui.checkBox")
local mapWidget = require("scripts.advanced_world_map.ui.mapWidget")
local borders = require("scripts.advanced_world_map.ui.borders")


local mapMarkerTexture = ui.texture{ path = commonData.mapMarkerPath }


local this = {}


this.cachedMapWidgetLayout = {}
this.cachedMapWidgetMetatable = {}

---@type table<string, advancedWorldMap.ui.mapElementMeta[]>
this.markersByName = nil

---@type table<string, advancedWorldMap.ui.mapElementMeta[]>
this.entranceMarkersByCellId = nil

---@type table<string, advancedWorldMap.ui.mapElementMeta[]>
this.markersByDoorHash = {}


function this.updateDiscoveredForCell(cell)
    local names = {}

    if cell.isExterior then
        for i = -1, 1 do
            for j = -1, 1 do
                names[commonData.exteriorCellIdFormat:format(cell.gridX + i, cell.gridY + j)] = true
            end
        end
    end
    names[cell.id] = true
    names[cell.name] = true
    names[stringLib.getBeforeComma(cell.name)] = true
    names[stringLib.getAfterComma(cell.name)] = true

    this.updateDiscovered(tableLib.keys(names))
end


---@param newDiscovered string[]
function this.updateDiscovered(newDiscovered)
    if not this.markersByName or not this.entranceMarkersByCellId then return end

    for _, name in pairs(newDiscovered or {}) do
        for _, handler in pairs(this.entranceMarkersByCellId[name] or {}) do
            local userData = handler:getUserData()
            if not userData or not userData.disabled then
                handler:setVisibility(true)
            end
        end
        for _, handler in pairs(this.markersByName[name] or {}) do
            local userData = handler:getUserData()
            if not userData or not userData.disabled then
                handler:setVisibility(true)
            end
            handler:setColor(config.data.ui.defaultLightColor)
        end
    end
end


---@param marker advancedWorldMap.ui.mapElementMeta
local function updateDoorMarkerVisibility(marker, visible)
    local userData = marker:getUserData()
    if not userData then return end

    if userData.type == "text" then
        marker:setVisibility(visible)
        userData.disabled = not visible
    else
        marker:setAlpha(visible and 1 or 0.25)
    end
end


function this.updateDoorMarkerVisibility(doorRef)
    local doorHash = commonData.doorHash(doorRef, types.Door.destCell(doorRef).id)
    local visible = not disabledDoors.contains(doorRef.id)

    local markers = this.markersByDoorHash[doorHash]
    if not markers then return end

    for _, marker in pairs(markers) do
        updateDoorMarkerVisibility(marker, visible)
    end
end


---@class advancedWorldMap.ui.menu.map
local menuMeta = {}
menuMeta.__index = menuMeta

menuMeta.menu = nil

function menuMeta:createMarkers()
    local widget = self.mapWidget
    local entrances = dynamicDataHandler.entrances or {}

    ---@type table<integer, advancedWorldMap.dynamicDataHandler.entranceData[]>
    local entranceByLine = {}
    local lineHeight = 256 * uiUtils.getUIScale()
    local lineDiff = lineHeight * 12

    for cellId, list in pairs(entrances) do
        for _, dt in pairs(list) do
            local line = math.floor(dt.pos.y / lineHeight)
            entranceByLine[line] = entranceByLine[line] or {}
            table.insert(entranceByLine[line], dt)
        end
    end

    for _, line in pairs(entranceByLine) do
        table.sort(line, function (a, b)
            return a.pos.x < b.pos.x
        end)
    end

    local markersByCellId = {}
    local markersByName = {}

    for _, line in pairs(entranceByLine) do
        for i, dt in ipairs(line) do
            local textAnchor = line[i + 1] and ((line[i + 1].pos.x - dt.pos.x) < lineDiff) and 1 or 0
            local imId = string.format("%d_%d_", dt.pos.x, dt.pos.y)
            local textId = imId..tostring(textAnchor)

            local cellId = cellLib.getCellIdByPos(dt.pos)
            markersByCellId[cellId] = markersByCellId[cellId] or {}
            markersByName[dt.name] = markersByName[dt.name] or {}
            this.markersByDoorHash[dt.doorHash] = this.markersByDoorHash[dt.doorHash] or {}

            local isCellDiscovered = not config.data.legend.onlyDiscovered or discoveredLocs.isDiscovered(cellId)

            local textMarkerHandler = widget:createTextMarker{
                id = textId,
                useCache = true,
                layerId = mapWidget.layerId.nonInteractive,
                text = (textAnchor == 0) and "  "..dt.name or dt.name.."  ",
                alpha = 0.5,
                anchor = util.vector2(textAnchor, 0.5),
                fontSize = 7,
                pos = dt.pos,
                color = discoveredLocs.isDiscovered(dt.name) and config.data.ui.defaultLightColor,
                showWhenZoomedIn = true,
                visible = isCellDiscovered,
                userData = {
                    type = "text",
                },
            }
            if textMarkerHandler then
                table.insert(markersByCellId[cellId], textMarkerHandler)
                table.insert(markersByName[dt.name], textMarkerHandler)
                table.insert(this.markersByDoorHash[dt.doorHash], textMarkerHandler)
                if disabledDoors.contains(dt.doorHash) then
                    updateDoorMarkerVisibility(textMarkerHandler, false)
                end
            end

            local imageMarkerHandler = widget:createImageMarker{
                id = imId,
                texture = mapMarkerTexture,
                useCache = true,
                layerId = mapWidget.layerId.marker,
                alpha = 0.5,
                anchor = util.vector2(0.5, 0.5),
                size = util.vector2(7, 7),
                pos = dt.pos,
                showWhenZoomedIn = true,
                visible = isCellDiscovered,
                searchText = stringLib.utf8_lower(dt.fullName),
                searchLabel = dt.fullName,
                userData = {
                    type = "image",
                    cellId = dt.id
                },
            }
            if imageMarkerHandler then
                table.insert(markersByCellId[cellId], imageMarkerHandler)
                table.insert(markersByName[dt.name], imageMarkerHandler)
                table.insert(this.markersByDoorHash[dt.doorHash], imageMarkerHandler)
                if disabledDoors.contains(dt.doorHash) then
                    updateDoorMarkerVisibility(imageMarkerHandler, false)
                end
            end

        end
    end

    ---@type table<string, advancedWorldMap.ui.mapElementMeta[]>
    this.entranceMarkersByCellId = markersByCellId

    for _, dt in pairs(dynamicDataHandler.cellNameData or {}) do
        local id = string.format("%s%d_%d", dt.name, dt.posX, dt.posY)

        local isCellDiscovered = not config.data.legend.onlyDiscovered or discoveredLocs.isDiscovered(dt.name)

        markersByName[dt.name] = markersByName[dt.name] or {}

        local textMarkerHandler = widget:createTextMarker{
            id = id,
            layerId = mapWidget.layerId.name,
            text = dt.name,
            anchor = util.vector2(0.5, 0.5),
            pos = util.vector2(dt.posX, dt.posY),
            color = discoveredLocs.isDiscovered(dt.name) and config.data.ui.defaultLightColor or config.data.ui.defaultColor,
            fontSize = 10 + math.min(8, dt.count) * 2,
            scaleFunc = mapWidget.scaleFunction.linear,
            alpha = 0.4,
            useCache = true,
            showWhenZoomedOut = true,
            visible = isCellDiscovered,
            searchText = stringLib.utf8_lower(dt.name),
        }
        if textMarkerHandler then
            table.insert(markersByName[dt.name], textMarkerHandler)
        end
    end

    ---@type table<string, advancedWorldMap.ui.mapElementMeta[]>
    this.markersByName = markersByName

    for _, info in pairs(dynamicDataHandler.regionNameData or {}) do
        local fontSize = 14 + math.min(8, info.count) * 3
        widget:createTextMarker{
            layerId = mapWidget.layerId.region,
            text = info.name,
            anchor = util.vector2(0.5, 0.5),
            pos = util.vector2(info.posX, info.posY),
            color = discoveredLocs.isDiscovered(info.name) and config.data.ui.defaultLightColor or config.data.ui.defaultColor,
            fontSize = fontSize,
            scaleFunc = mapWidget.scaleFunction.linear,
            alpha = 0.12,
            showWhenZoomedOut = true,
            useCache = true,
            searchText = stringLib.utf8_lower(info.name),
            searchLabel = l10n("Region")..": "..info.name
        }
    end
end


---@return boolean
function menuMeta:openWidget(id)
    local widget = self.widgets[id]
    if not widget then return false end

    if self.activeWidgetId == id then
        if widget.params.onClose then widget.params.onClose() end
        self.widgetWindowLayout.content = ui.content{}
        self.activeWidgetId = nil
    else
        if self.activeWidgetId then
            local widgetData = self.widgets[self.activeWidgetId]
            if widgetData and widgetData.params.onClose then
                widgetData.params.onClose()
            end
            self.widgetWindowLayout.content = ui.content{}
            self.activeWidgetId = nil
        end

        if widget.params.onOpen then widget.params.onOpen(self.widgetWindowLayout.content) end
        self.activeWidgetId = id
    end

    self:updateMapWidgetWidth()
    return true
end


function menuMeta:closeActiveWidget()
    if not self.activeWidgetId then return end

    local widgetData = self.widgets[self.activeWidgetId]
    if widgetData and widgetData.params.onClose then
        widgetData.params.onClose()
    end
    self.widgetWindowLayout.content = ui.content{}
    self.activeWidgetId = nil

    self:updateMapWidgetWidth()
end


---@class advancedWorldMap.ui.menu.addHeaderElement.params
---@field id string
---@field layout table
---@field onOpen fun(content)?
---@field onClose fun()?

---@param params advancedWorldMap.ui.menu.addHeaderElement.params
function menuMeta:addWidget(params)
    if not params or not params.id or not params.layout then return end

    local origEvents = params.layout.events or {}

    params.layout.props = params.layout.props or {}
    params.layout.props.anchor = util.vector2(0.5, 0.5)

    local pressed = false

    params.layout.events = {
        focusLoss = async:callback(function(e, layout)
            pressed = false
            if origEvents.focusLoss then origEvents.focusLoss(e, layout) end
        end),

        mousePress = async:callback(function(e, layout)
            pressed = true
            if origEvents.mousePress then origEvents.mousePress(e, layout) end
        end),

        mouseRelease = async:callback(function(e, layout)
            if origEvents.mouseRelease then origEvents.mouseRelease(e, layout) end

            if pressed then
                self:openWidget(params.id)
                self:update()
            end
            pressed = false
        end),
    }

    self.widgets[params.id] = {layout = params.layout, params = params}

    uiUtils.removeFromContent(self.widgetHeaderLayout.content, params.id)
    self.widgetHeaderLayout.content:add(interval(self.params.fontSize, 1))
    self.widgetHeaderLayout.content:add(params.layout)
end


---@param cellId string?
---@return table? layout
---@return advancedWorldMap.ui.mapWidgetMeta? meta
---@return boolean? isNew
function menuMeta:getMapWidgetForCell(cellId)
    local cellKeyId = cellId or commonData.exteriorMapId

    local isNew = false
    if not this.cachedMapWidgetLayout[cellKeyId] then
        this.cachedMapWidgetLayout[cellKeyId], this.cachedMapWidgetMetatable[cellKeyId] = mapWidget.new{
            updateFunc = self.update,
            size = self.mainSize,
            position = util.vector2(0, 0),
            cellId = cellId
        }
        isNew = true
    else
        this.cachedMapWidgetMetatable[cellKeyId]:setSize(self.mainSize)
    end

    return this.cachedMapWidgetLayout[cellKeyId], this.cachedMapWidgetMetatable[cellKeyId], isNew
end


---@param cellId string?
---@return boolean changed
function menuMeta:updateMapWidgetCell(cellId)
    if cellId == commonData.exteriorMapId or cellId and cellId:find(commonData.exteriorCellLabel) then cellId = nil end
    if self.mapWidget and self.mapWidget.cellId == cellId then return false end

    local lay, meta, isNew = self:getMapWidgetForCell(cellId)
    if not lay or not meta then return false end

    local oldZoom = self.mapWidget and self.mapWidget.zoom or meta.zoom or 1

    self.mainLayout.content[1].content[2] = lay
    self.mapWidget = meta

    if isNew then
        eventSys.triggerEvent(eventSys.events.onMapInitialized, {menu = self, mapWidget = meta, cellId = cellId})
    end

    self.mapWidget:setUpdateFunction(self.update)
    self.mapWidget:updatePlayerMarker(self.centerOnPlayer)
    self.mapWidget:setZoom(oldZoom)

    eventSys.triggerEvent(eventSys.events.onMapShown, {menu = self, mapWidget = meta, cellId = cellId})

    return true
end


function menuMeta:getHeaderHeight()
    return self.headerHeight
end


function menuMeta:close()
    if not self.menu then return end
    self.menu:destroy()
end


---@class advencedWorldMap.ui.menu.map.create.params
---@field relativePosition any?
---@field relativeSize any?
---@field fontSize number?
---@field onClose function?


---@param params advencedWorldMap.ui.menu.map.create.params
---@return advancedWorldMap.ui.menu.map
function this.create(params)
    if not params then params = {} end

    ---@class advancedWorldMap.ui.menu.map
    local meta = setmetatable({}, menuMeta)

    meta.params = params

    if not params.fontSize then params.fontSize = config.data.ui.fontSize end
    if not params.relativeSize then
        params.relativeSize = util.vector2(config.data.main.relativeSize.x / 100, config.data.main.relativeSize.y / 100)
    end
    if not params.relativePosition then
        params.relativePosition = util.vector2(config.data.main.relativePosition.x / 100, config.data.main.relativePosition.y / 100)
    end

    local screenSize = uiUtils.getScaledScreenSize()
    meta.size = screenSize:emul(params.relativeSize)

    local headerHeight = params.fontSize * 1.25
    meta.headerHeight = headerHeight
    local headerSize = util.vector2(meta.size.x, headerHeight)

    local mainSize = util.vector2(meta.size.x, meta.size.y - headerHeight)
    meta.mainSize = mainSize

    meta.centerOnPlayer = false

    ---@type table<string, {layout : table, params : advancedWorldMap.ui.menu.addHeaderElement.params}>
    menuMeta.widgets = {}
    ---@type string?
    menuMeta.activeWidgetId = nil

    meta.widgetHeaderLayout = {
        type = ui.TYPE.Flex,
        name = commonData.mapWidgetHeaderLayoutId,
        props = {
            horizontal = true,
            anchor = util.vector2(0, 0.5),
            relativePosition = util.vector2(0, 0.5),
        },
        userData = {

        },
        content = ui.content {

        }
    }

    meta.widgetWindowLayout = {
        type = ui.TYPE.Flex,
        name = commonData.mapWidgetHeaderLayoutId,
        props = {
            horizontal = true,
            position = util.vector2(2, 2),
            align = ui.ALIGNMENT.Center,
            arrange = ui.ALIGNMENT.Center,
        },
        userData = {

        },
        content = ui.content {

        }
    }

    meta.update = function ()
        meta.menu:update()
    end

    local headerLayout = {
        type = ui.TYPE.Widget,
        props = {
            size = headerSize,
        },
        userData = {

        },
        events = {
            mousePress = async:callback(function(coord, layout)
                layout.userData.lastMousePos = util.vector2(coord.position.x / screenSize.x, coord.position.y / screenSize.y)
            end),

            mouseRelease = async:callback(function(_, layout)
                local relativePos = meta.menu.layout.props.relativePosition
                config.setValue("main.relativePosition.x", relativePos.x * 100)
                config.setValue("main.relativePosition.y", relativePos.y * 100)
                layout.userData.lastMousePos = nil

                meta:update()
            end),

            mouseMove = async:callback(function(coord, layout)
                if not layout.userData.lastMousePos then return end

                local props = meta.menu.layout.props
                local relativePos = util.vector2(coord.position.x / screenSize.x, coord.position.y / screenSize.y)

                props.relativePosition = props.relativePosition - (layout.userData.lastMousePos - relativePos)
                meta:update()

                layout.userData.lastMousePos = relativePos
            end),
        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                props = {
                    resource = commonData.whiteTexture,
                    relativeSize = util.vector2(1, 1),
                    color = config.data.ui.backgroundColor,
                    alpha = config.data.ui.headerBackgroundAlpha / 100,
                }
            },
            meta.widgetHeaderLayout,
            {
                type = ui.TYPE.Text,
                props = {
                    text = l10n("Close"),
                    textSize = params.fontSize * 1.4,
                    autoSize = true,
                    anchor = util.vector2(1, 0.5),
                    relativePosition = util.vector2(1, 0.5),
                    textColor = config.data.ui.defaultColor,
                    textShadow = true,
                    textShadowColor = config.data.ui.shadowColor,
                    propagateEvents = false,
                },
                userData = {},
                events = {
                    mouseRelease = async:callback(function(_, layout)
                        if params.onClose then params.onClose() end
                        meta.menu:destroy()
                    end),
                }
            }
        }
    }

    eventSys.registerHandler(eventSys.events.onMapInitialized, function (e)
        if e.cellId ~= nil then return end
        meta:createMarkers()
    end)

    meta.getWidgetWindowWidth = function (self)
        local widgetWindowWidth = 0
        for _, el in pairs(meta.widgetWindowLayout.content) do
            if el.props and el.props.size then
                widgetWindowWidth = widgetWindowWidth + el.props.size.x
            end
        end
        return widgetWindowWidth
    end

    meta.updateMapWidgetWidth = function (self)
        local mapWidgetSize = util.vector2(math.max(1, self.mainSize.x - meta:getWidgetWindowWidth()), self.mainSize.y)
        self.mapWidget:setSize(mapWidgetSize)
    end

    local mainLayout
    mainLayout = {
        type = ui.TYPE.Widget,
        props = {
            size = mainSize,
            position = util.vector2(0, headerHeight),
        },
        userData = {

        },
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = {
                    size = mainSize,
                    horizontal = true
                },
                userData = {

                },
                content = ui.content {
                    meta.widgetWindowLayout,
                    {
                        type = ui.TYPE.Widget,
                    },
                }
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = uiUtils.whiteTexture,
                    alpha = 0.3,
                    size = util.vector2(config.data.ui.resizerSize, config.data.ui.resizerSize),
                    anchor = util.vector2(1, 1),
                    relativePosition = util.vector2(1, 1),
                },
                userData = {

                },
                events = {
                    mousePress = async:callback(function(e, layout)
                        layout.userData.lastMousePos = e.position
                    end),

                    mouseRelease = async:callback(function(_, layout)
                        layout.userData.lastMousePos = nil
                        meta.mapWidget:setZoom(meta.mapWidget.zoom)
                        meta:update()
                    end),

                    mouseMove = async:callback(function(e, layout)
                        local lastPos = layout.userData.lastMousePos
                        if not lastPos then return end

                        meta:closeActiveWidget()

                        local posDif = util.vector2(e.position.x - lastPos.x, e.position.y - lastPos.y)
                        local minSize = util.vector2(100, 100)

                        local mapSize = meta.mapWidget:getSize()
                        local newSize = util.vector2(math.max(minSize.x, mapSize.x + posDif.x), math.max(minSize.y, mapSize.y + posDif.y))

                        meta.mapWidget:setSize(newSize)
                        mainLayout.props.size = util.vector2(meta:getWidgetWindowWidth() + newSize.x, newSize.y)
                        meta.mainSize = mainLayout.props.size

                        local hSize = headerLayout.props.size
                        headerLayout.props.size = util.vector2(mainLayout.props.size.x, hSize.y)

                        local size = util.vector2(meta.mainSize.x, meta.mainSize.y + hSize.y)
                        meta.menu.layout.props.size = size
                        meta.size = size

                        config.setValue("main.relativeSize.x", size.x / screenSize.x * 100)
                        config.setValue("main.relativeSize.y", size.y / screenSize.y * 100)

                        eventSys.triggerEvent(eventSys.events["onResized"], {
                            menuSize = size,
                            mapWidgetSize = newSize
                        })

                        meta:update()

                        layout.userData.lastMousePos = e.position
                    end),
                },
            },
            borders(),
        },
    }

    meta.mainLayout = mainLayout

    meta:updateMapWidgetCell(not playerRef.cell.isExterior and playerRef.cell.id or nil)

    local layout = {
        type = ui.TYPE.Widget,
        layer = "Windows",
        props = {
            size = meta.size,
            relativePosition = params.relativePosition,
        },
        userData = {
            meta = meta,
        },
        content = ui.content {
            headerLayout,
            mainLayout,
        }
    }

    meta.menu = ui.create(layout)


    local function onMouseWheelCallback(content, value)
        for _, dt in pairs(content) do
            if not type(dt) == "table" then goto continue end
            if dt.userData and dt.userData.onMouseWheel then
                dt.userData.onMouseWheel(value)
            end

            if dt.content then
                onMouseWheelCallback(dt.content, value)
            end

            ::continue::
        end
    end

    meta.onMouseWheel = function (self, vertical)
        local layout = meta.menu.layout
        onMouseWheelCallback(layout.content, vertical)
    end

    meta.onMouseClick = function (self, buttonId)

    end


    local func
    func = function ()
        if meta.menu.layout then
            if meta.mapWidget:updatePlayerMarker(meta.centerOnPlayer) then
                meta:update()
            end
            async:newUnsavableSimulationTimer(0.15, func)
        end
    end
    async:newUnsavableSimulationTimer(0.15, func)

    eventSys.triggerEvent(eventSys.events["onMenuOpened"], {menu = meta})

    return meta
end


return this