local async = require('openmw.async')
local ui = require('openmw.ui')
local util = require('openmw.util')
local core = require('openmw.core')
local input = require('openmw.input')
local vfs = require('openmw.vfs')

local playerRef = require("openmw.self")

local config = require("scripts.advanced_world_map.config.configLib")
local commonData = require("scripts.advanced_world_map.common")

local localStorage = require("scripts.advanced_world_map.storage.localStorage")
local dataHandler = require("scripts.advanced_world_map.mapDataHandler")
local dynamicDataHandler = require("scripts.advanced_world_map.dynamicDataHandler")
local realTimer = require("scripts.advanced_world_map.realTimer")
local playerPos = require("scripts.advanced_world_map.playerPosition")
local playerMarker = require("scripts.advanced_world_map.ui.playerMarker")
local discoveredLocs = require("scripts.advanced_world_map.discoveredLocations")
local eventSys = require("scripts.advanced_world_map.eventSys")

local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local uiUtils = require("scripts.advanced_world_map.ui.utils")
local cellLib = require("scripts.advanced_world_map.utils.cell")
local log = require("scripts.advanced_world_map.utils.log")

local tooltip = require("scripts.advanced_world_map.ui.tooltip")

local mapElement = require("scripts.advanced_world_map.ui.mapElement")

local l10n = core.l10n(commonData.l10nKey)


local mapMarkerTexture = ui.texture{ path = commonData.mapMarkerPath }
local playerMarkerTexture = ui.texture{ path = commonData.playerMapMarkerPath }

local worldMapTexture

local zoomInOffsetInWorldCoord = 16384
local zoomOutOffsetInWorldCoord = 24576



local this = {}

local uniquesId = 0
this.getUniqueId = function ()
    uniquesId = uniquesId + 1
    return uniquesId
end


---@class advancedWorldMap.ui.mapWidget.layerId
this.layerId = {
    map = 1,
    region = 2,
    name = 3,
    player = 4,
    nonInteractive = 5,
    marker = 6,
}


---@class advancedWorldMap.ui.mapWidget.scaleFunctions
this.scaleFunction = {}

function this.scaleFunction.linear(size, zoom)
    return size * zoom
end


function this.scaleFunction.marker(size, zoom)
    return size * math.sqrt(math.sqrt(zoom))
end


function this.scaleFunction.playerMarker(size, zoom)
    if zoom > 1 then
        return size * zoom ^ 0.2
    end
    return size
end


---@class advancedWorldMap.ui.mapWidget.region
---@field left number
---@field right number
---@field top number
---@field bottom number


---@param region advancedWorldMap.ui.mapWidget.region
---@param x number
---@param y number
---@return boolean
function this.isPointInRegion(region, x, y)
    return x >= region.left and x <= region.right and y >= region.bottom and y <= region.top
end


---@class advancedWorldMap.ui.mapWidgetMeta
local mapWidgetMeta = {}
mapWidgetMeta.__index = mapWidgetMeta

mapWidgetMeta.layerIds = this.layerId
mapWidgetMeta.scaleFunctions = this.scaleFunction

mapWidgetMeta.getUniqueId = function (self)
    return this.getUniqueId()
end


function mapWidgetMeta:getDisplaySize(scale)
    local baseSize = self.displayMapSize or util.vector2(self.mapInfo.width, self.mapInfo.height)
    if scale then
        return baseSize * scale
    end
    return baseSize
end


function mapWidgetMeta:getPadding(scale)
    local padding = self.borderPadding or util.vector2(0, 0)
    if scale then
        return padding * scale
    end
    return padding
end


function mapWidgetMeta:getMapLayersLayout()
    return self.layout.content[2]
end

function mapWidgetMeta:getLayerLayout(id)
    return self.layers[id]
end

function mapWidgetMeta:getMapLayout()
    return self:getLayerLayout(this.layerId.map)
end

function mapWidgetMeta:getRegionLayout()
    return self:getLayerLayout(this.layerId.region)
end

function mapWidgetMeta:getNameLayout()
    return self:getLayerLayout(this.layerId.name)
end

function mapWidgetMeta:getMarkerLayout()
    return self:getLayerLayout(this.layerId.marker)
end

function mapWidgetMeta:getPlayerLayout()
    return self:getLayerLayout(this.layerId.player)
end


function mapWidgetMeta:getRelativeCenter()
    return util.vector2(
        (0 - self.mapInfo.gridX.min) / (self.mapInfo.gridX.max - self.mapInfo.gridX.min + 1),
        (0 - self.mapInfo.gridY.min) / (self.mapInfo.gridY.max - self.mapInfo.gridY.min + 1)
    )
end


function mapWidgetMeta:getRelativeRotationPivot()
    local center = self:getRelativeCenter()
    return util.vector2(center.x, 1 - center.y)
end


function mapWidgetMeta:getRotationPivot(scale)
    local pivot = self:getRelativeRotationPivot()

    local width = self.mapInfo.width * (scale or 1)
    local height = self.mapInfo.height * (scale or 1)
    local padding = self:getPadding(scale or 1)

    return util.vector2(padding.x + pivot.x * width, padding.y + pivot.y * height)
end


function mapWidgetMeta:getRelativePositionByWorldPosition(worldPos)
    local center = self:getRelativeCenter()
    local x = worldPos.x / 8192
    local y = worldPos.y / 8192

    local relX = center.x + x * self.mapInfo.pixelsPerCell / self.mapInfo.width
    local relY = 1 - center.y - y * self.mapInfo.pixelsPerCell / self.mapInfo.height

    local mapWidth = self.mapInfo.width
    local mapHeight = self.mapInfo.height
    local padding = self:getPadding()
    local displaySize = self:getDisplaySize()

    local containerPos = util.vector2(relX * mapWidth + padding.x, relY * mapHeight + padding.y)

    if self.northDirectionAngle and self.northDirectionAngle ~= 0 then
        local pivot = self:getRotationPivot()
        containerPos = (containerPos - pivot):rotate(-self.northDirectionAngle) + pivot
    end

    return util.vector2(containerPos.x / displaySize.x, containerPos.y / displaySize.y)
end


function mapWidgetMeta:getAbsolutePositionByWorldPosition(worldPos, ignoreNorthAngle)
    local cellX = worldPos.x / 8192
    local cellY = worldPos.y / 8192
    local x = (cellX - self.mapInfo.gridX.min) * self.mapInfo.pixelsPerCell
    local y = (self.mapInfo.gridY.max - cellY) * self.mapInfo.pixelsPerCell

    local padding = self:getPadding()
    local pos = util.vector2(x + padding.x, y + padding.y)

    if not ignoreNorthAngle and self.northDirectionAngle and self.northDirectionAngle ~= 0 then
        local pivot = self:getRotationPivot()
        pos = (pos - pivot):rotate(-self.northDirectionAngle) + pivot
    end

    return pos * self.zoom
end


function mapWidgetMeta:getRelativePositionOfCursor()
    local main = self.layout
    local mouseOffset = main.userData.mainMouseOffset + main.userData.additiveMouseOffset
    local widget = self:getMapLayersLayout()
    local mapPos = widget.props.position
    local mapSize = widget.props.size

    local relX = (mouseOffset.x - mapPos.x) / mapSize.x
    local relY = (mouseOffset.y - mapPos.y) / mapSize.y

    return util.vector2(relX, relY)
end


function mapWidgetMeta:getWorldPositionByRelativePosition(relPos)
    local displaySize = self:getDisplaySize()
    local paddingScaled = self:getPadding(self.zoom)

    local containerBasePos = util.vector2(relPos.x * displaySize.x, relPos.y * displaySize.y)
    local containerPos = containerBasePos * self.zoom

    if self.northDirectionAngle and self.northDirectionAngle ~= 0 then
        local pivot = self:getRotationPivot(self.zoom)
        containerPos = (containerPos - pivot):rotate(self.northDirectionAngle) + pivot
    end

    local mapPos = util.vector2(containerPos.x - paddingScaled.x, containerPos.y - paddingScaled.y)

    local zoomedPixPerCell = self.mapInfo.pixelsPerCell * self.zoom
    local zoomedPixelSize = 8192 / zoomedPixPerCell
    local zoomedXOffset = self.mapInfo.gridX.min * zoomedPixPerCell
    local zoomedYOffset = (self.mapInfo.gridY.max + 1) * zoomedPixPerCell

    return util.vector2(
        (mapPos.x + zoomedXOffset) * zoomedPixelSize,
        (-mapPos.y + zoomedYOffset) * zoomedPixelSize
    )
end


local function clampAndCenterPosition(pos, mapSize, mainSize)
    local newX, newY

    if mapSize.x * 4 <= mainSize.x then
        newX = (mainSize.x - mapSize.x) / 2
    else
        newX = util.clamp(pos.x, mainSize.x - mapSize.x * 4, mapSize.x * 3)
    end

    if mapSize.y * 4 <= mainSize.y then
        newY = (mainSize.y - mapSize.y) / 2
    else
        newY = util.clamp(pos.y, mainSize.y - mapSize.y * 4, mapSize.y * 3)
    end

    return util.vector2(newX, newY)
end


---@return advancedWorldMap.ui.mapWidget.region rect
function mapWidgetMeta:getVisibleMapRect()
    local widget = self:getMapLayersLayout()
    local mapPos = widget.props.position
    local mapSize = widget.props.size
    local mainSize = self.layout.props.size

    local left = math.max(0, -mapPos.x)
    local top = math.max(0, -mapPos.y)
    local right = math.min(mapSize.x, -mapPos.x + mainSize.x)
    local bottom = math.min(mapSize.y, -mapPos.y + mainSize.y)

    return {
        left = left,
        top = top,
        right = right,
        bottom = bottom,
    }
end


---@return advancedWorldMap.ui.mapWidget.region rectInWorldCoordinates
---@return advancedWorldMap.ui.mapWidget.region rect
function mapWidgetMeta:getVisibleMapRectInWorldCoordinates()
    local rect = self:getVisibleMapRect()

    local zoomedPixPerCell = self.mapInfo.pixelsPerCell * self.zoom
    local pixelSize = 8192 / zoomedPixPerCell
    local xOffset = self.mapInfo.gridX.min * zoomedPixPerCell
    local yOffset = self.mapInfo.gridY.max * zoomedPixPerCell
    local paddingScaled = self:getPadding(self.zoom)

    local function toWorld(x, y)
        local pos = util.vector2(x, y)

        if self.northDirectionAngle and self.northDirectionAngle ~= 0 then
            local pivot = self:getRotationPivot(self.zoom)
            pos = (pos - pivot):rotate(-self.northDirectionAngle) + pivot
        end

        pos = util.vector2(pos.x - paddingScaled.x, pos.y - paddingScaled.y)

        return util.vector2((pos.x + xOffset) * pixelSize, (-pos.y + yOffset) * pixelSize)
    end

    local left = toWorld(rect.left, 0).x
    local top = toWorld(0, rect.top).y
    local right = toWorld(rect.right, 0).x
    local bottom = toWorld(0, rect.bottom).y

    return { left = left, top = top, right = right, bottom = bottom }, rect
end


function mapWidgetMeta:getWorldPositionOfVisibleCenter()
    local rect = self:getVisibleMapRect()

    local zoomedPixPerCell = self.mapInfo.pixelsPerCell * self.zoom
    local pixelSize = 8192 / zoomedPixPerCell
    local xOffset = self.mapInfo.gridX.min * zoomedPixPerCell
    local yOffset = self.mapInfo.gridY.max * zoomedPixPerCell
    local paddingScaled = self:getPadding(self.zoom)

    local centerX = (rect.left + rect.right) / 2
    local centerY = (rect.top + rect.bottom) / 2

    local pos = util.vector2(centerX, centerY)

    if self.northDirectionAngle and self.northDirectionAngle ~= 0 then
        local pivot = self:getRotationPivot(self.zoom)
        pos = (pos - pivot):rotate(-self.northDirectionAngle) + pivot
    end

    pos = util.vector2(pos.x - paddingScaled.x, pos.y - paddingScaled.y)

    return util.vector2((pos.x + xOffset) * pixelSize, (-pos.y + yOffset) * pixelSize)
end


function mapWidgetMeta:getRelativePositionOfVisibleCenter()
    local rect = self:getVisibleMapRect()
    local centerX = (rect.left + rect.right) / 2
    local centerY = (rect.top + rect.bottom) / 2

    local pos = util.vector2(centerX, centerY)

    if self.northDirectionAngle and self.northDirectionAngle ~= 0 then
        local pivot = self:getRotationPivot(self.zoom)
        pos = (pos - pivot):rotate(-self.northDirectionAngle) + pivot
    end

    local displaySize = self:getDisplaySize()
    local posBase = pos / self.zoom
    local relX = posBase.x / displaySize.x
    local relY = posBase.y / displaySize.y

    return util.vector2(relX, relY)
end


function mapWidgetMeta:getSize()
    return self.layout.props.size
end

function mapWidgetMeta:setSize(newSize)
    self.maxZoom = math.min(newSize.x / self.mapInfo.pixelsPerCell, newSize.y / self.mapInfo.pixelsPerCell) * 3
    local displaySize = self:getDisplaySize()
    self.minZoom = math.min(newSize.x / displaySize.x, newSize.y / displaySize.y) / 2
    self.layout.props.size = newSize
end


function mapWidgetMeta:updateOnZoomMarkers()
    local visibleRect = self:getVisibleMapRectInWorldCoordinates()
    if self.cellId or self.zoom >= config.data.tileset.zoomToShow then
        visibleRect.bottom = visibleRect.bottom - zoomInOffsetInWorldCoord
        visibleRect.top = visibleRect.top + zoomInOffsetInWorldCoord
        visibleRect.left = visibleRect.left - zoomInOffsetInWorldCoord
        visibleRect.right = visibleRect.right + zoomInOffsetInWorldCoord
        self:removeOnZoomMarkers(self._lastOnZoomZoom == self.zoom and visibleRect or nil)
        self:createZoomInMarkers(visibleRect)
        self:placeGroundTextures(visibleRect)
    else
        visibleRect.bottom = visibleRect.bottom - zoomOutOffsetInWorldCoord
        visibleRect.top = visibleRect.top + zoomOutOffsetInWorldCoord
        visibleRect.left = visibleRect.left - zoomOutOffsetInWorldCoord
        visibleRect.right = visibleRect.right + zoomOutOffsetInWorldCoord
        self:removeOnZoomMarkers(self._lastOnZoomZoom == self.zoom and visibleRect or nil)
        self:createZoomOutMarkers(visibleRect)
        self:removeGroundTextures()
    end
    self._lastOnZoomZoom = self.zoom
end


---@param self advancedWorldMap.ui.mapWidgetMeta
local function setZoom(self, zoom, relativePos)
    local widget = self:getMapLayersLayout()

    local oldZoom = self.zoom
    local oldSize = self:getDisplaySize(oldZoom)

    zoom = util.clamp(zoom, self.minZoom, self.maxZoom)

    local newSize = self:getDisplaySize(zoom)
    local oldPos = widget.props.position

    local mainSize = self.layout.props.size

    local newPos
    if relativePos then
        newPos = util.vector2(
            -relativePos.x * newSize.x + mainSize.x / 2,
            -relativePos.y * newSize.y + mainSize.y / 2
        )
    else
        local mouseOffset = self.layout.userData.mainMouseOffset + self.layout.userData.additiveMouseOffset
        local mouseOnMap = mouseOffset - oldPos

        local rel = util.vector2(mouseOnMap.x / oldSize.x, mouseOnMap.y / oldSize.y)
        newPos = mouseOffset - rel:emul(newSize)
    end

    newPos = clampAndCenterPosition(newPos, newSize, mainSize)

    widget.props.size = newSize
    widget.props.position = newPos
    self.zoom = zoom

    self:updateOnZoomMarkers()

    self:updateMarkersScale()

    if self.cellId then
        localStorage.data[commonData.localMapZoomFieldId] = zoom
    else
        localStorage.data[commonData.worldMapZoomFieldId] = zoom
    end

    if oldZoom ~= zoom then
        eventSys.triggerEvent(eventSys.events.onZoomed, {mapWidget = self, zoom = zoom})
    end
end

---@param zoom number
function mapWidgetMeta:setZoom(zoom, relativePos)
    setZoom(self, zoom, relativePos or self:getRelativePositionOfVisibleCenter())
end


function mapWidgetMeta:focusOnWorldPosition(worldPos)
    local widget = self:getMapLayersLayout()
    local mainSize = self.layout.props.size

    local relPos = self:getRelativePositionByWorldPosition(worldPos)
    local mapSize = widget.props.size
    local newPos = util.vector2(
        mapSize.x * relPos.x - mainSize.x / 2,
        mapSize.y * relPos.y - mainSize.y / 2
    ) * -1

    newPos = clampAndCenterPosition(newPos, widget.props.size, mainSize)

    widget.props.position = newPos
end


function mapWidgetMeta:updateMarkersScale()
    local playerMarkerLayout = self:getPlayerLayout()

    local playerMarkerImageSize = this.scaleFunction.playerMarker(playerMarkerLayout.content[1].userData.size, self.zoom)

    playerMarkerLayout.content[1].props.size = playerMarkerImageSize
    playerMarkerLayout.content[1].props.resource = playerMarker.getTexture(self.northDirectionAngle) or playerMarkerTexture

    for _, layout in pairs({self:getLayerLayout(this.layerId.nonInteractive), self:getLayerLayout(this.layerId.marker),
            self:getLayerLayout(this.layerId.name), self:getLayerLayout(this.layerId.region)}) do
        for i, elem in pairs(layout.content) do
            if elem.userData and elem.userData.autoScale then
                if elem.userData.text then
                    elem.props = {
                        text = elem.props.text,
                        autoSize = elem.props.autoSize,
                        anchor = elem.props.anchor,
                        relativePosition = elem.props.relativePosition,
                        textColor = elem.props.textColor,
                        textSize = (elem.userData.scaleFunc or this.scaleFunction.marker)(elem.userData.fontSize, self.zoom),
                        visible = elem.props.visible,
                        alpha = elem.props.alpha,
                    }
                elseif elem.userData.texture then
                    elem.props.size = (elem.userData.scaleFunc or this.scaleFunction.marker)(elem.userData.size, self.zoom)
                end
            end
        end
    end
end


function mapWidgetMeta:updateMarkers()
    setZoom(self, self.zoom)
end


local createMarkerFuncCache = {}

---@class advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
---@field layerId integer,
---@field id string?
---@field pos any in the game world
---@field texture any ui.texture
---@field events table?
---@field tooltipContent any
---@field size any util.vector2
---@field color any util.color.rgb
---@field anchor any util.vector2
---@field alpha number?
---@field visible boolean?
---@field showWhenZoomedIn boolean?
---@field showWhenZoomedOut boolean?
---@field scaleFunc (fun(size: any, zoom: number): number)?
---@field useCache boolean?
---@field searchText string? lowercase
---@field searchLabel string?
---@field userData table?

---@class advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params
---@field layerId integer
---@field id string?
---@field pos any in the game world
---@field text string
---@field events table?
---@field tooltipContent any
---@field fontSize number?
---@field size any util.vector2
---@field color any util.color.rgb
---@field anchor any util.vector2
---@field textAlignH any ui.ALIGNMENT
---@field alpha number?
---@field visible boolean?
---@field showWhenZoomedIn boolean?
---@field showWhenZoomedOut boolean?
---@field scaleFunc (fun(size: any, zoom: number): number)?
---@field useCache boolean?
---@field searchText string? lowercase
---@field searchLabel string?
---@field userData table?


---@param self advancedWorldMap.ui.mapWidgetMeta
---@param params advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
---@return string? id
---@return integer? layerId
---@return advancedWorldMap.ui.mapElementMeta?
---@return any? layout
local function createMarker(self, params, onlyInitialize)
    if not params then params = {layerId = this.layerId.marker} end
    if not params.layerId then return end

    local content = self:getLayerLayout(params.layerId).content

    if params.id and uiUtils.isExistsInContent(content, params.id) then
        return params.id, params.layerId, content[params.id].userData.markerElement, content[params.id]
    end

    local function addZoomInOutData(id, layout)
        if self.zoomMarkersCellIdById[id] then return end

        if params.showWhenZoomedIn then
            local cellId = layout.userData.cellId or cellLib.getCellIdByPos(params.pos)
            self.zoomInMarkers[cellId] = self.zoomInMarkers[cellId] or {}
            self.zoomInMarkers[cellId][id] = {
                id = id,
                params = params
            }
            self.zoomMarkersCellIdById[id] = cellId
            layout.userData.showWhenZoomedIn = true
            layout.userData.cellId = cellId
            table.insert(self.activeZoomMarkers, {id, params.layerId, layout.userData.markerElement})
        end
        if params.showWhenZoomedOut then
            local cellId = layout.userData.cellId or cellLib.getCellIdByPos(params.pos)
            self.zoomOutMarkers[cellId] = self.zoomOutMarkers[cellId] or {}
            self.zoomOutMarkers[cellId][id] = {
                id = id,
                params = params
            }
            self.zoomMarkersCellIdById[id] = cellId
            layout.userData.showWhenZoomedOut = true
            layout.userData.cellId = cellId
            table.insert(self.activeZoomMarkers, {id, params.layerId, layout.userData.markerElement})
        end
    end

    params.pos = params.pos or util.vector3(0, 0, 0)
    local relPos = self:getRelativePositionByWorldPosition(params.pos)

    if not onlyInitialize and params.useCache and params.id then
        local id = params.id
        local cacheId = id.."_"..tostring(params.layerId)
        local cachedLayout = createMarkerFuncCache[cacheId]
        if cachedLayout then
            addZoomInOutData(id, cachedLayout)

            if cachedLayout.userData.forceChanged then
                cachedLayout.userData.markerElement:restoreLayout()
                -- cachedLayout.props = {
                --     text = params.text,
                --     textSize = params.text and (params.scaleFunc or this.scaleFunction.marker)(params.fontSize or 18, self.zoom),
                --     anchor = params.anchor or util.vector2(0.5, 0.5),
                --     relativePosition = relPos,
                --     textColor = params.text and (params.color or config.data.ui.defaultColor),
                --     visible = params.visible,
                --     alpha = params.alpha or 1,
                --     resource = params.texture,
                --     size = params.size and (params.scaleFunc or this.scaleFunction.marker)(params.size, self.zoom),
                --     color = params.texture and (params.color or config.data.ui.defaultColor),
                --     propagateEvents = false,
                -- }
                -- cachedLayout.userData.scaleFunc = params.scaleFunc
                -- cachedLayout.userData.autoScale = true
                -- cachedLayout.userData.fontSize = params.text and (params.fontSize or 18) or nil
                -- cachedLayout.userData.size = params.size
                -- cachedLayout.userData.forceChanged = false
            else
                cachedLayout.props.relativePosition = relPos
            end

            if cachedLayout.props.textSize then
                cachedLayout.props.textSize = (cachedLayout.userData.scaleFunc or this.scaleFunction.marker)(cachedLayout.userData.fontSize, self.zoom)
            end
            if cachedLayout.props.size then
                cachedLayout.props.size = (cachedLayout.userData.scaleFunc or this.scaleFunction.marker)(cachedLayout.userData.size, self.zoom)
            end
            local res = uiUtils.safeAddToContent(content, cachedLayout)
            if res then
                eventSys.triggerEvent(eventSys.events.onMapElementCreated, {mapWidget = self, marker = cachedLayout.userData.markerElement})
                return id, params.layerId, cachedLayout.userData.markerElement, cachedLayout
            else
                return
            end
        end
    end

    local fontSize = params.fontSize or 18
    local color = params.color or config.data.ui.defaultColor
    local alpha = params.alpha or 1
    local anchor = params.anchor or util.vector2(0.5, 0.5)
    local tooltipContent = params.tooltipContent

    local size = params.size
    local texture = params.texture

    local events = params.events or {}

    params.id = params.id or tostring(self:getUniqueId())
    ---@type string
    local markerName = params.id

    local marker
    marker = {
        type = params.text and ui.TYPE.Text or ui.TYPE.Image,
        name = markerName,
        props = {
            text = params.text,
            textSize = params.text and fontSize and (params.scaleFunc or this.scaleFunction.marker)(fontSize, self.zoom),
            autoSize = size == nil,
            anchor = anchor,
            relativePosition = relPos,
            textColor = params.text and color,
            visible = params.visible,
            alpha = alpha,
            resource = texture,
            size = size and (params.scaleFunc or this.scaleFunction.marker)(size, self.zoom),
            color = params.texture and color,
            propagateEvents = false,
        },
        userData = {
            scaleFunc = params.scaleFunc,
            autoScale = true,
            fontSize = params.text and fontSize,
            size = size,
            params = params,
            userData = params.userData,
            pressed = {}
        },
        events = {
            focusLoss = async:callback(function(e, layout)
                self.layout.userData.inFocus = false
                marker.userData.pressed = {}
                if events.focusLoss then events.focusLoss(e, layout) end
                self.layout.events.focusLoss(e, layout, layout.userData.markerElement)
                tooltip.destroy(layout)
            end),

            mouseMove = async:callback(function(e, layout)
                self.layout.userData.inFocus = true
                self.layout.userData.additiveMouseOffset = e.offset

                if events.mouseMove then events.mouseMove(e, layout) end
                self.layout.events.mouseMove({offset = e.offset, position = e.position}, layout, layout.userData.markerElement)

                if not tooltipContent then return end
                tooltip.createOrMove(e, layout, tooltipContent)
            end),

            mousePress = async:callback(function(e, layout)
                marker.userData.pressed[e.button] = true
                if events.mousePress then events.mousePress(e, layout) end
                self.layout.events.mousePress(e, layout, layout.userData.markerElement)
            end),

            mouseRelease = async:callback(function(e, layout)
                if events.mouseRelease then events.mouseRelease(e, layout, marker.userData.pressed[e.button] or false) end
                marker.userData.pressed[e.button] = false
                self.layout.events.mouseRelease(e, layout, layout.userData.markerElement)
            end),
        }
    }

    createMarkerFuncCache[markerName.."_"..tostring(params.layerId)] = marker

    local markerELement = mapElement.new(self, markerName, params.layerId, params, marker)
    marker.userData.markerElement = markerELement

    addZoomInOutData(markerName, marker)

    if onlyInitialize then
        return markerName, params.layerId, markerELement, marker
    end

    if uiUtils.safeAddToContent(content, marker) then
        eventSys.triggerEvent(eventSys.events.onMapElementCreated, {mapWidget = self, marker = markerELement})
    else
        return
    end

    return markerName, params.layerId, markerELement, marker
end


---@param params advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
---@return advancedWorldMap.ui.mapElementMeta?
function mapWidgetMeta:createImageMarker(params)
    if not params.texture then return end
    local id, layerId, element = createMarker(self, params, (params.showWhenZoomedIn or params.showWhenZoomedOut) and true)
    return element
end

---@param params advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params
---@return advancedWorldMap.ui.mapElementMeta?
function mapWidgetMeta:createTextMarker(params)
    if not params.text then return end
    local id, layerId, element = createMarker(self, params, (params.showWhenZoomedIn or params.showWhenZoomedOut) and true)
    return element
end


local function removeMarker(self, id, layer)
    if not id or not layer then return end
    local content = self:getLayerLayout(layer).content

    uiUtils.removeFromContent(content, id)
end

function mapWidgetMeta:removeMarker(id, layer)
    removeMarker(self, id, layer)
    if id and self.zoomMarkersCellIdById[id] then
        (self.zoomInMarkers[self.zoomMarkersCellIdById[id]] or {})[id] = nil
        (self.zoomOutMarkers[self.zoomMarkersCellIdById[id]] or {})[id] = nil
        self.zoomMarkersCellIdById[id] = nil
    end
end


---@return advancedWorldMap.ui.mapElementMeta?
function mapWidgetMeta:forceChangeMarker(id, layerId, propsParams)
    local success, markerLayout = pcall(function ()
        local layout = self:getLayerLayout(layerId)
        return layout.content[id]
    end)

    if success and markerLayout then
        tableLib.copy(propsParams, markerLayout.props)
        markerLayout.userData.forceChanged = true
        return
    end

    local cellId = self.zoomMarkersCellIdById[id]
    if not cellId then return end

    for _, tb in pairs({self.zoomOutMarkers, self.zoomInMarkers}) do
        if tb[cellId] and tb[cellId][id] then
            local mId, lId, markerELement, lay = createMarker(self, tb[cellId][id].params)
            if lay then
                tableLib.copy(propsParams, lay.props)
                lay.userData.forceChanged = true
            end
        end
    end
end




---@param region advancedWorldMap.ui.mapWidget.region
function mapWidgetMeta:createZoomOutMarkers(region)
    local minGridX = math.floor(region.left / 8192)
    local maxGridX = math.ceil(region.right / 8192)
    local minGridY = math.floor(region.bottom / 8192)
    local maxGridY = math.ceil(region.top / 8192)
    for x = minGridX, maxGridX do
        for y = minGridY, maxGridY do
            local cellId = cellLib.getCellIdByGrid(x, y)

            for _, dt in pairs(self.zoomOutMarkers[cellId] or {}) do
                if dt.params.text then
                    table.insert(self.activeZoomMarkers, {createMarker(self, dt.params)})
                else
                    table.insert(self.activeZoomMarkers, {createMarker(self, dt.params)})
                end
            end
        end
    end

    self.onZoomMarkersCenter = util.vector2(
        (minGridX + maxGridX) / 2 * 8192,
        (minGridY + maxGridY) / 2 * 8192
    )
end



---@param region advancedWorldMap.ui.mapWidget.region
function mapWidgetMeta:createZoomInMarkers(region)
    local minGridX = math.floor(region.left / 8192)
    local maxGridX = math.ceil(region.right / 8192)
    local minGridY = math.floor(region.bottom / 8192)
    local maxGridY = math.ceil(region.top / 8192)
    for x = minGridX, maxGridX do
        for y = minGridY, maxGridY do
            local cellId = commonData.exteriorCellIdFormat:format(x, y)

            for _, dt in pairs(self.zoomInMarkers[cellId] or {}) do
                if dt.params.text then
                    table.insert(self.activeZoomMarkers, {createMarker(self, dt.params)})
                else
                    table.insert(self.activeZoomMarkers, {createMarker(self, dt.params)})
                end
            end

        end
    end

    self.onZoomMarkersCenter = util.vector2(
        (minGridX + maxGridX) / 2 * 8192,
        (minGridY + maxGridY) / 2 * 8192
    )
end


---@param allowRect advancedWorldMap.ui.mapWidget.region?
function mapWidgetMeta:removeOnZoomMarkers(allowRect)
    if allowRect then
        for i, dt in pairs(self.activeZoomMarkers) do
            local markerPos = dt[3]._params.pos or {x = 0, y = 0}
            if not this.isPointInRegion(allowRect, markerPos.x, markerPos.y) then
                removeMarker(self, dt[1], dt[2])
                self.activeZoomMarkers[i] = nil
                eventSys.triggerEvent(eventSys.events.onMapElementRemoved, {mapWidget = self, marker = dt[3]})
            end
        end
    else
        for i, dt in pairs(self.activeZoomMarkers) do
            removeMarker(self, dt[1], dt[2])
            self.activeZoomMarkers[i] = nil
            eventSys.triggerEvent(eventSys.events.onMapElementRemoved, {mapWidget = self, marker = dt[3]})
        end
    end
end


function mapWidgetMeta:removeGroundTextures()
    local mapLayoutContent = self:getMapLayout().content
    for i = #mapLayoutContent, 2, -1 do
        uiUtils.removeFromContent(mapLayoutContent, i)
    end
end


---@param region advancedWorldMap.ui.mapWidget.region
function mapWidgetMeta:placeGroundTextures(region)
    self:removeGroundTextures()

    if self.localCellInfo then
        if self.cellStatics then
            for _, dt in pairs(self.cellStatics) do
                createMarker(self, {
                    layerId = self.layerIds.map,
                    texture = uiUtils.whiteTexture,
                    color = util.color.rgb(0.15, 0.15, 0.10),
                    pos = util.vector2(dt[1], dt[2]),
                    size = util.vector2(dt[3] / 8192 * self.mapInfo.pixelsPerCell + 1, dt[4] / 8192 * self.mapInfo.pixelsPerCell + 1),
                    scaleFunc = self.scaleFunctions.linear,
                    anchor = util.vector2(0.5, 0.5)
                })
            end

            return
        end

        local mapLayout = self:getMapLayout()

        local tileHeight = util.round(self.mapInfo.pixelsPerCell * self.zoom)
        local tileSize = util.vector2(tileHeight, tileHeight)
        local startPos = self:getAbsolutePositionByWorldPosition(
            util.vector2(
                self.mapInfo.gridX.min * 8192,
                self.mapInfo.gridY.min * 8192
            ),
            true
        )

        for y = 1, self.localCellInfo.height do
            for x = 1, self.localCellInfo.width do
                local texture = (self.mapTexture[y] or {})[x]
                if not texture then goto continue end

                local pos = util.vector2(startPos.x + tileHeight * (x - 1), startPos.y - tileHeight * (y - 1))

                mapLayout.content:add{
                    type = ui.TYPE.Image,
                    props = {
                        resource = texture,
                        size = tileSize,
                        position = pos
                    }
                }

                ::continue::
            end
        end

    else
        local minGridX = math.floor(region.left / 8192)
        local maxGridX = math.ceil(region.right / 8192)
        local minGridY = math.floor(region.bottom / 8192)
        local maxGridY = math.ceil(region.top / 8192)

        local startPos = self:getAbsolutePositionByWorldPosition(util.vector2(8192 * minGridX, 8192 * minGridY))
        local tileHeight = util.round(self.mapInfo.pixelsPerCell * self.zoom)
        local tileSize = util.vector2(tileHeight, tileHeight)

        local mapLayout = self:getMapLayout()
        for x = 0, maxGridX - minGridX - 1 do
            for y = 0, maxGridY - minGridY - 1 do
                local texture = dataHandler.getLocalMapTexture(minGridX + x, minGridY + y)

                local cellId = cellLib.getCellIdByGrid(minGridX + x, minGridY + y)
                local isDiscovered = not config.data.tileset.onlyDiscovered or discoveredLocs.isDiscovered(cellId)

                if not texture or not isDiscovered then goto continue end

                local pos = util.vector2(startPos.x + tileHeight * x, startPos.y - tileHeight * y)

                mapLayout.content:add{
                    type = ui.TYPE.Image,
                    props = {
                        resource = texture,
                        size = tileSize,
                        position = pos
                    }
                }

                ::continue::
            end
        end
    end
end



---@param focusOnPlayer boolean?
---@return boolean
function mapWidgetMeta:updatePlayerMarker(focusOnPlayer)
    local lay = self:getPlayerLayout()
    if lay.props.visible == false then return false end

    local playerMarkerLayout = lay.content[1]
    local playerCell = playerRef.cell
    if self.cellId ~= (not playerCell.isExterior and playerRef.cell.id or nil) then
        local visible = playerMarkerLayout.props.visible
        playerMarkerLayout.props.visible = false
        return visible ~= false
    else
        playerMarkerLayout.props.visible = true
    end
    local exPos = self.cellId and playerRef.position or playerPos.gexExteriorPos()
    local dist = (playerMarkerLayout.userData.lastPos - exPos):length()

    local yaw = playerRef.rotation:getYaw()
    local lastYaw = playerMarkerLayout.userData.lastYaw

    if dist < (8192 / (self.mapInfo.pixelsPerCell * self.zoom)) and (math.abs(yaw - lastYaw) < 0.1) then return false end

    local playerRelPos = self:getRelativePositionByWorldPosition(exPos)
    playerMarkerLayout.props.relativePosition = playerRelPos
    playerMarkerLayout.props.resource = playerMarker.getTexture(self.northDirectionAngle) or playerMarkerTexture
    playerMarkerLayout.userData.lastPos = exPos
    playerMarkerLayout.userData.lastYaw = yaw

    if focusOnPlayer then
        self:focusOnWorldPosition(exPos)
    end

    return true
end


function mapWidgetMeta:setUpdateFunction(func)
    self.update = func
end


function mapWidgetMeta:closeRightMouseMenu()
    local interactiveLayout = self:getLayerLayout(this.layerId.marker)
    uiUtils.removeFromContent(interactiveLayout.content, commonData.rightClickMenuId)
end


local function getDefaultLayerLayout()
    return {
        type = ui.TYPE.Widget,
        props = {
            position = util.vector2(0, 0),
            relativeSize = util.vector2(1, 1),
            visible = false,
        },
        userData = {},
        content = ui.content {

        },
    }
end


function mapWidgetMeta:setLayerVisibility(layerId, visible)
    local layout = self:getLayerLayout(layerId)

    if not layout then return false end

    if visible then
        self:getMapLayersLayout().content[layerId] = self.layers[layerId]
    else
        self:getMapLayersLayout().content[layerId] = getDefaultLayerLayout()
    end

    return true
end

---@return boolean?
function mapWidgetMeta:getLayerVisibility(layerId)
    local layout = self:getLayerLayout(layerId)
    if layout then
        return layout.props.visible ~= false
    end
end


---@return advancedWorldMap.ui.mapElementMeta[]
function mapWidgetMeta:getActiveMarkers()
    local markers = {}
    for _, dt in pairs(self.activeZoomMarkers) do
        if dt[3] then
            table.insert(markers, dt[3])
        end
    end
    return markers
end


---@class advancedWorldMap.ui.mapWidget.params
---@field size any
---@field fontSize integer?
---@field position any?
---@field relativePosition any?
---@field anchor any?
---@field cellId string?
---@field updateFunc function

---@param params advancedWorldMap.ui.mapWidget.params
---@return table?
---@return advancedWorldMap.ui.mapWidgetMeta?
function this.new(params)

    params.fontSize = params.fontSize or 18

    ---@class advancedWorldMap.ui.mapWidgetMeta
    local meta = setmetatable({}, mapWidgetMeta)

    meta.params = params
    meta.cellId = params.cellId
    ---@type number[][] {x, y, width, height}
    meta.cellStatics = nil

    local mapLayout

    if params.cellId then
        local localCellInfo = dataHandler.getLocalCellInfo(params.cellId)
        if not localCellInfo.mX then
            localCellInfo = {
                height = 5,
                width = 5,
                mX = 1280,
                mY = -1280,
                nA = 0,
            }
            core.sendGlobalEvent("AdvWMap:getMapStatics", {cellId = params.cellId})
        end

        local mapTextures = dataHandler.getLocalCellMapTextures(params.cellId)
        if not mapTextures then mapTextures = {} end

        local width = localCellInfo.width * 256
        local height = localCellInfo.height * 256

        local mapInfo = {
            width = width,
            height = height,
            pixelsPerCell = 256,
            gridX = {
                min = -localCellInfo.mX / 512,
                max = -localCellInfo.mX / 512 + localCellInfo.width - 1,
            },
            gridY = {
                min = (-localCellInfo.height - localCellInfo.mY / 512),
                max = (-localCellInfo.height - localCellInfo.mY / 512) + localCellInfo.height - 1
            },
        }

        meta.localCellInfo = localCellInfo
        meta.mapTexture = mapTextures
        meta.mapInfo = mapInfo
        meta.northDirectionAngle = localCellInfo.nA or 0

        local padding = mapInfo.pixelsPerCell * 0.5
        meta.borderPadding = util.vector2(padding, padding)
        meta.displayMapSize = util.vector2(mapInfo.width + padding * 2, mapInfo.height + padding * 2)

        mapLayout = {
            type = ui.TYPE.Widget,
            props = {
                position = util.vector2(0, 0),
                relativeSize = util.vector2(1, 1),
            },
            userData = {},
            content = ui.content{
                {
                    type = ui.TYPE.Widget,
                },
            },
        }

    else
        if not worldMapTexture then
            if not dataHandler.mapInfo or not dataHandler.mapImagePath then return end

            local mapImagePath = dataHandler.mapImagePath

            if not vfs.fileExists(mapImagePath) then return end

            worldMapTexture = ui.texture{ path = mapImagePath }
        end

        meta.mapTexture = worldMapTexture
        meta.mapInfo = dataHandler.mapInfo

        local padding = dataHandler.mapInfo.pixelsPerCell * 0.5
        meta.borderPadding = util.vector2(padding, padding)
        meta.displayMapSize = util.vector2(meta.mapInfo.width + padding * 2, meta.mapInfo.height + padding * 2)

        mapLayout = {
            type = ui.TYPE.Widget,
            props = {
                position = util.vector2(0, 0),
                relativeSize = util.vector2(1, 1),
            },
            userData = {},
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = worldMapTexture,
                        relativePosition = util.vector2(meta.borderPadding.x / meta.displayMapSize.x, meta.borderPadding.y / meta.displayMapSize.y),
                        relativeSize = util.vector2(meta.mapInfo.width / meta.displayMapSize.x, meta.mapInfo.height / meta.displayMapSize.y),
                    }
                },
            },
        }
    end


    meta.borderPadding = meta.borderPadding or util.vector2(0, 0)
    meta.displayMapSize = meta.displayMapSize or util.vector2(meta.mapInfo.width, meta.mapInfo.height)

    ---@type table<string, table<string, {id : string, params : advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params}>> by cell id, by marker id
    meta.zoomInMarkers = {}
    ---@type table<string, table<string, {id : string, params : advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params}>> by cell id, by marker id
    meta.zoomOutMarkers = {}
    ---@type table<string, string>
    meta.zoomMarkersCellIdById = {}
    ---@type {[2] : string, [1] : integer, [3] : advancedWorldMap.ui.mapElementMeta}[] {marker Id, layer}
    meta.activeZoomMarkers = {}

    if meta.cellId then
        meta.zoom = localStorage.data[commonData.localMapZoomFieldId] or 2
    else
        meta.zoom = localStorage.data[commonData.worldMapZoomFieldId] or 1
    end
    meta.maxZoom = math.min(params.size.x / meta.mapInfo.pixelsPerCell, params.size.y / meta.mapInfo.pixelsPerCell) * 3
    local displaySize = meta:getDisplaySize()
    meta.minZoom = math.min(params.size.x / displaySize.x, params.size.y / displaySize.y) / 2

    meta._lastOnZoomZoom = -1

    meta.update = function(self)
        params.updateFunc()
    end

    local mapLayers = {
        mapLayout,
        -- for region names
        {
            type = ui.TYPE.Widget,
            props = {
                position = util.vector2(0, 0),
                relativeSize = util.vector2(1, 1),
            },
            userData = {},
            content = ui.content {

            },
        },
        -- for city names
        {
            type = ui.TYPE.Widget,
            props = {
                position = util.vector2(0, 0),
                relativeSize = util.vector2(1, 1),
            },
            userData = {},
            content = ui.content {

            },
        },
        -- player marker
        {
            type = ui.TYPE.Widget,
            props = {
                position = util.vector2(0, 0),
                relativeSize = util.vector2(1, 1),
            },
            userData = {},
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        relativePosition = meta:getRelativePositionByWorldPosition(playerPos.gexExteriorPos()),
                        resource = playerMarker.getTexture(meta.northDirectionAngle) or playerMarkerTexture,
                        size = util.vector2(32, 32),
                        anchor = util.vector2(0.5, 0.5),
                        color = config.data.ui.defaultColor,
                        visible = true,
                        alpha = 0.6,
                    },
                    userData = {
                        size = util.vector2(32, 32),
                        lastPos = playerPos.gexExteriorPos(),
                        lastYaw = playerRef.rotation:getYaw(),
                        lastNorthAngle = meta.northDirectionAngle or 0,
                    },
                },
            },
        },
        -- for noninteractive markers
        {
            type = ui.TYPE.Widget,
            props = {
                position = util.vector2(0, 0),
                relativeSize = util.vector2(1, 1),
            },
            userData = {},
            content = ui.content {

            },
        },
        -- for interactive markers
        {
            type = ui.TYPE.Widget,
            props = {
                position = util.vector2(0, 0),
                relativeSize = util.vector2(1, 1),
            },
            userData = {},
            content = ui.content {

            },
        },
    }

    meta.layers = tableLib.copy(mapLayers)

    local main
    main = {
        type = ui.TYPE.Widget,
        props = {
            size = params.size,
            position = params.position,
            relativePosition = params.relativePosition,
            anchor = params.anchor,
        },
        userData = {
            meta = meta,
            onMouseWheel = function(value)
                if not meta.layout.userData.inFocus then return end
                setZoom(meta, value > 0 and meta.zoom * 1.25 or meta.zoom * 0.75)
                meta:update()
            end,

            inFocus = false,
            mainMouseOffset = util.vector2(0, 0),
            additiveMouseOffset = util.vector2(0, 0),
        },
        events = {
            mousePress = async:callback(function(e, layout, markerElement)
                if meta.layout.userData.hasActiveMenu then
                    local interactiveLayout = meta:getLayerLayout(this.layerId.marker)
                    uiUtils.removeFromContent(interactiveLayout.content, commonData.rightClickMenuId)
                    meta:update()
                    meta.layout.userData.hasActiveMenu = nil
                end

                e.marker = markerElement
                if markerElement then
                    e.offset = main.userData.mainMouseOffset + e.offset
                end

                if eventSys.triggerEvent(eventSys.events["onMousePress"], e) then
                    main.userData.lastMousePos = nil
                    return
                end

                if e.button == 1 then
                    main.userData.lastMousePos = e.position
                end
            end),

            mouseRelease = async:callback(function(e, layout, markerElement)
                e.marker = markerElement
                if markerElement then
                    e.offset = main.userData.mainMouseOffset + e.offset
                end
                if eventSys.triggerEvent(eventSys.events["onMouseRelease"], e) then
                    main.userData.lastMousePos = nil
                    return
                end

                if e.button == 3 then
                    if eventSys.isContainsHandler(eventSys.events["onRightMouseMenu"]) then
                        local interactiveLayout = meta:getLayerLayout(this.layerId.marker)
                        uiUtils.removeFromContent(interactiveLayout.content, commonData.rightClickMenuId)

                        local relPos = meta:getRelativePositionOfCursor()
                        local lay = {
                            name = commonData.rightClickMenuId,
                            type = ui.TYPE.Flex,
                            props = {
                                autoSize = true,
                                relativePosition = relPos,
                                propagateEvents = false,
                            },
                            content = ui.content{

                            },
                        }
                        local layContent = lay.content
                        eventSys.triggerEvent(eventSys.events["onRightMouseMenu"], {
                            relPos = relPos,
                            content = layContent,
                        })

                        if #layContent > 0 then
                            interactiveLayout.content:add(lay)
                            meta:update()
                            meta.layout.userData.hasActiveMenu = true
                        end
                    end
                elseif e.button == 1 then
                    main.userData.lastMousePos = nil
                end
            end),

            focusLoss = async:callback(function(_, layout, markerElement)
                main.userData.lastMousePos = nil
                main.userData.inFocus = false
                if eventSys.triggerEvent(eventSys.events["onFocusLoss"], {marker = markerElement}) then
                    main.userData.lastMousePos = nil
                    return
                end
            end),

            mouseMove = async:callback(function(e, layout, markerElement)
                if not markerElement then
                    main.userData.mainMouseOffset = e.offset
                    main.userData.additiveMouseOffset = util.vector2(0, 0)
                end
                main.userData.inFocus = true

                if eventSys.triggerEvent(eventSys.events["onMouseMove"], {
                        position = e.position, offset = main.userData.mainMouseOffset + main.userData.additiveMouseOffset,
                        marker = markerElement}) then
                    main.userData.lastMousePos = nil
                    return
                end

                if not main.userData.lastMousePos then return end

                local props = meta:getMapLayersLayout().props
                local mainSize = main.props.size
                local mapSize = props.size

                local newX = props.position.x - (main.userData.lastMousePos.x - e.position.x)
                local newY = props.position.y - (main.userData.lastMousePos.y - e.position.y)
                local newPos = util.vector2(newX, newY)

                newPos = clampAndCenterPosition(newPos, mapSize, mainSize)
                props.position = newPos

                if meta.onZoomMarkersCenter then
                    local centerWorldPos = meta:getWorldPositionOfVisibleCenter()

                    local dist = (meta.onZoomMarkersCenter - centerWorldPos):length()
                    if dist > zoomInOffsetInWorldCoord * 0.5 then
                        meta:updateOnZoomMarkers()
                    end
                end

                meta:update()

                main.userData.lastMousePos = e.position
            end),
        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                props = {
                    resource = commonData.whiteTexture,
                    relativeSize = util.vector2(1, 1),
                    color = meta.cellId and commonData.mapInteriorBackgroundColor or commonData.mapWaterColor,
                }
            },
            {
                type = ui.TYPE.Widget,
                props = {
                    position = util.vector2(0, 0),
                    size = util.vector2(meta.displayMapSize.x, meta.displayMapSize.y),
                },
                userData = {},
                content = ui.content {
                    table.unpack(meta.layers)
                }
            }
        }
    }

    meta.layout = main

    meta:setZoom(meta.zoom, meta:getRelativePositionByWorldPosition(meta.cellId and util.vector2(0, 0) or playerPos.gexExteriorPos()))

    return main, meta
end


return this