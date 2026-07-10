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
local mapTextureHandler = require("scripts.advanced_world_map.mapTextureHandler")
local mapDataHandler = require("scripts.advanced_world_map.mapDataHandler")
local realTimer = require("scripts.advanced_world_map.realTimer")
local playerPos = require("scripts.advanced_world_map.playerPosition")
local playerMarker = require("scripts.advanced_world_map.ui.playerMarker")
local discoveredLocs = require("scripts.advanced_world_map.discoveredLocations")
local eventSys = require("scripts.advanced_world_map.eventSys")
local menuMode = require("scripts.advanced_world_map.ui.menuMode")

local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local uiUtils = require("scripts.advanced_world_map.ui.utils")
local cellLib = require("scripts.advanced_world_map.utils.cell")
local log = require("scripts.advanced_world_map.utils.log")

local tooltip = require("scripts.advanced_world_map.ui.tooltip")
local interval = require("scripts.advanced_world_map.ui.interval")

local mapElement = require("scripts.advanced_world_map.ui.mapElement")

local l10n = core.l10n(commonData.l10nKey)


local playerMarkerTexture = ui.texture{ path = commonData.playerMapMarkerPath }



local this = {}

this.playerMarkerMenu = nil
this.lastMouseWheelTimestamp = 0
this.mouseWheelCount = 0
this.mouseWheelTimer = nil

function this.destroyPlayerMarkerMenu()
    if this.playerMarkerMenu and this.playerMarkerMenu.layout then
        this.playerMarkerMenu:destroy()
    end
    this.playerMarkerMenu = nil
end

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
    nonInteractive = 4,
    transport = 5,
    player = 6,
    marker = 7,
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
    if zoom < 1 then
        return size * zoom ^ 0.5
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


function this.compareRegions(region1, region2)
    return region1.left == region2.left and region1.right == region2.right and
        region1.top == region2.top and region1.bottom == region2.bottom
end


---@class advancedWorldMap.ui.mapWidgetMeta
local mapWidgetMeta = {}
mapWidgetMeta.__index = mapWidgetMeta

mapWidgetMeta.LAYER = this.layerId

mapWidgetMeta.getUniqueId = function (self)
    return this.getUniqueId()
end

mapWidgetMeta.isPointInRegion = this.isPointInRegion
mapWidgetMeta.isRegionEqual = this.compareRegions


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
    local cellSize = self.mapInfo.cellSize or 8192
    local x = worldPos.x / cellSize
    local y = worldPos.y / cellSize

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
    local cellSize = self.mapInfo.cellSize or 8192
    local cellX = worldPos.x / cellSize
    local cellY = worldPos.y / cellSize
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
    local mouseOffset = main.userData.mainMouseOffset
    local widget = self:getMapLayersLayout()
    local mapPos = widget.props.position
    local mapSize = widget.props.size

    local relX = (mouseOffset.x - mapPos.x) / mapSize.x
    local relY = (mouseOffset.y - mapPos.y) / mapSize.y

    return util.vector2(relX, relY)
end


function mapWidgetMeta:getScreenPositionOfCursor()
    local mouseOffset = self.layout.userData.mousePos
    return mouseOffset
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

    local cellSize = self.mapInfo.cellSize or 8192
    local zoomedPixPerCell = self.mapInfo.pixelsPerCell * self.zoom
    local zoomedPixelSize = cellSize / zoomedPixPerCell
    local zoomedXOffset = self.mapInfo.gridX.min * zoomedPixPerCell
    local zoomedYOffset = (self.mapInfo.gridY.max + 1) * zoomedPixPerCell

    return util.vector2(
        (mapPos.x + zoomedXOffset) * zoomedPixelSize,
        (-mapPos.y + zoomedYOffset) * zoomedPixelSize
    )
end


local function clampAndCenterPosition(pos, mapSize, mainSize)
    local newX, newY

    if mapSize.x * 2 <= mainSize.x then
        newX = (mainSize.x - mapSize.x) / 2
    else
        newX = util.clamp(pos.x, mainSize.x - mapSize.x * 2, mapSize.x)
    end

    if mapSize.y * 2 <= mainSize.y then
        newY = (mainSize.y - mapSize.y) / 2
    else
        newY = util.clamp(pos.y, mainSize.y - mapSize.y * 2, mapSize.y)
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

    local cellSize = self.mapInfo.cellSize or 8192
    local zoomedPixPerCell = self.mapInfo.pixelsPerCell * self.zoom
    local pixelSize = cellSize / zoomedPixPerCell
    local xOffset = self.mapInfo.gridX.min * zoomedPixPerCell
    local yOffset = (self.mapInfo.gridY.max + 1) * zoomedPixPerCell
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

    local cellSize = self.mapInfo.cellSize or 8192
    local zoomedPixPerCell = self.mapInfo.pixelsPerCell * self.zoom
    local pixelSize = cellSize / zoomedPixPerCell
    local xOffset = self.mapInfo.gridX.min * zoomedPixPerCell
    local yOffset = (self.mapInfo.gridY.max + 1) * zoomedPixPerCell
    local paddingScaled = self:getPadding(self.zoom)

    local centerX = (rect.left + rect.right) / 2
    local centerY = (rect.top + rect.bottom) / 2

    local pos = util.vector2(centerX, centerY)

    if self.northDirectionAngle and self.northDirectionAngle ~= 0 then
        local pivot = self:getRotationPivot(self.zoom)
        pos = (pos - pivot):rotate(self.northDirectionAngle) + pivot
    end

    pos = util.vector2(pos.x - paddingScaled.x, pos.y - paddingScaled.y)

    return util.vector2((pos.x + xOffset) * pixelSize, (-pos.y + yOffset) * pixelSize)
end


function mapWidgetMeta:getRelativePositionOfVisibleCenter()
    local widget = self:getMapLayersLayout()
    local mapPos = widget.props.position
    local mainSize = self.layout.props.size

    local pos = util.vector2(mainSize.x / 2 - mapPos.x, mainSize.y / 2 - mapPos.y)

    local displaySize = self:getDisplaySize()
    local posBase = pos / self.zoom
    local relX = posBase.x / displaySize.x
    local relY = posBase.y / displaySize.y

    return util.vector2(relX, relY)
end


function mapWidgetMeta:getSize()
    return self.layout.props.size
end


local function roundMinZoom(self)
    local mapInfo = not self.cellId and config.data.data.altExMapInfo or self.mapInfo
    local tileSize = (mapInfo.tileSize or (mapInfo.pixelsPerCell * 16))
    local targetPixels = math.floor((tileSize * self.minZoom) / self._zoomRoundingMul) * self._zoomRoundingMul
    self.minZoom = targetPixels / tileSize
end


function mapWidgetMeta:setSize(newSize)
    local screenSize = uiUtils.getScaledScreenSize()
    local uiScale = uiUtils.getUIScale()
    self.maxZoom = screenSize.x / (self.mapInfo.pixelsPerCell * self.eScale) * 5
    local divVal = self.cellId and 6 or 3
    self.minZoom = math.min(screenSize.x / self.mapInfo.width / divVal, self.mapInfo.pixelsPerCell / (divVal * self.eScale * uiScale))

    roundMinZoom(self)

    self.layout.props.size = newSize
end


function mapWidgetMeta:setLayoutPosition(pos)
    self.layout.props.position = pos
end


function mapWidgetMeta:isInZoomInMode()
    return self.cellId ~= nil or self.zoom >= self:getZoomModeThreshold()
end


function mapWidgetMeta:getZoomModeThreshold()
    return config.data.tileset.zoomToShow / (self.eScale * self.uiScale)
end


function mapWidgetMeta:updateOnZoomMarkers(force)
    local visibleRect = self:getVisibleMapRectInWorldCoordinates()

    local isInZoomInMode = self:isInZoomInMode()
    local size = self:getSize()
    local paddingBase = isInZoomInMode and 2048 or 4096
    local mul = paddingBase / (self.mapInfo.pixelsPerCell * self.zoom)
    local minPadding = self.inActiveMode and 8192 or 2048
    local paddingX = math.max(minPadding, size.x * mul)
    local paddingY = math.max(minPadding, size.y * mul)
    local halfPaddingX = paddingX * 0.5
    local halfPaddingY = paddingY * 0.5

    if self.inActiveMode then
        visibleRect.bottom = math.floor((visibleRect.bottom - paddingY) / 8192) * 8192
        visibleRect.top = math.floor((visibleRect.top + paddingY) / 8192) * 8192 + 8191
        visibleRect.left = math.floor((visibleRect.left - paddingX) / 8192) * 8192
        visibleRect.right = math.floor((visibleRect.right + paddingX) / 8192) * 8192 + 8191
    else
        visibleRect.bottom = visibleRect.bottom - paddingY
        visibleRect.top = visibleRect.top + paddingY
        visibleRect.left = visibleRect.left - paddingX
        visibleRect.right = visibleRect.right + paddingX
    end

    self._markerRect = visibleRect
    self._markerRectLimited = {
        bottom = visibleRect.bottom + halfPaddingY,
        top = visibleRect.top - halfPaddingY,
        left = visibleRect.left + halfPaddingX,
        right = visibleRect.right - halfPaddingX
    }

    if eventSys.triggerEvent(eventSys.EVENT.onZoomMarkersUpdate, {mapWidget = self, region = visibleRect}) then
        return
    end

    local updateOnlyRect = not force and self._lastOnZoomZoomInMode == isInZoomInMode

    if isInZoomInMode then
        self:removeOnZoomMarkers(updateOnlyRect and visibleRect or nil)
        self:placeGroundTextures(visibleRect)
        self:createZoomInMarkers(visibleRect, nil, not updateOnlyRect or force)
    else
        self:removeOnZoomMarkers(updateOnlyRect and visibleRect or nil)
        self:placeGroundTextures(visibleRect)
        self:createZoomOutMarkers(visibleRect, nil, force)
    end
    self._lastOnZoomZoom = self.zoom
    self._lastOnZoomZoomInMode = isInZoomInMode
end


---@param self advancedWorldMap.ui.mapWidgetMeta
local function setZoom(self, zoom, relativePos, force, skipRounding)
    local widget = self:getMapLayersLayout()

    local oldZoom = self.zoom
    local oldSize = self:getDisplaySize(oldZoom)

    if not skipRounding then
        local mapInfo = not self.cellId and config.data.data.altExMapInfo or self.mapInfo
        local tileSize = (mapInfo.tileSize or (mapInfo.pixelsPerCell * 16))
        -- Round the zoom so that the dimensions of both tiles (when using altExMapInfo) are whole numbers of pixels,
        -- which will ensure that the tiles are placed correctly without gaps
        local function getNewZoom(zm)
            local targetPixels = math.floor((tileSize * zm) / self._zoomRoundingMul) * self._zoomRoundingMul
            local newZoom = util.clamp(targetPixels / tileSize, self.minZoom, self.maxZoom)
            return newZoom
        end
        local newZoom = getNewZoom(zoom)

        -- for cases where the zoom calculation result is rounded to the same value as the old zoom
        if zoom ~= oldZoom and newZoom == oldZoom then
            local step = self._zoomRoundingMul / tileSize * (zoom > oldZoom and 1 or -1)
            newZoom = getNewZoom(zoom + step)
        end

        zoom = newZoom
    end

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
        local mouseOffset = self.layout.userData.mainMouseOffset
        local mouseOnMap = mouseOffset - oldPos

        local rel = util.vector2(mouseOnMap.x / oldSize.x, mouseOnMap.y / oldSize.y)
        newPos = mouseOffset - rel:emul(newSize)
    end

    newPos = clampAndCenterPosition(newPos, newSize, mainSize)

    widget.props.size = newSize
    widget.props.position = newPos
    self.zoom = zoom

    self:updateOnZoomMarkers(force)

    self:updateMarkersScale()

    if self.cellId then
        localStorage.data[commonData.localMapZoomFieldId] = zoom * self.eScale
    else
        localStorage.data[commonData.worldMapZoomFieldId] = zoom * self.eScale
    end

    if oldZoom ~= zoom then
        eventSys.triggerEvent(eventSys.EVENT.onZoomed, {mapWidget = self, zoom = zoom})
    end
    tooltip.destroyLast()
end

---@param zoom number
function mapWidgetMeta:setZoom(zoom, relativePos, useScale, skipRounding)
    if useScale then
        zoom = zoom / self.eScale
    end
    setZoom(self, zoom, relativePos or self:getRelativePositionOfVisibleCenter(), nil, skipRounding == true)
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

    local playerMarkerImageSize = self.SCALE_FUNCTION.playerMarker(playerMarkerLayout.content[1].userData.size, self.zoom)

    playerMarkerLayout.content[1].props.size = playerMarkerImageSize
    playerMarkerLayout.content[1].props.resource = playerMarker.getTexture(self.northDirectionAngle) or playerMarkerTexture

    local isInZoomInMode = self:isInZoomInMode()
    -- Some markers may be stuck after zooming out and I don't know why.
    -- TODO: Investigate why this happens and fix it properly. For now, just remove the stucked markers.
    local stuckedMarkers = {}

    for _, layout in pairs({self:getLayerLayout(this.layerId.nonInteractive), self:getLayerLayout(this.layerId.marker),
            self:getLayerLayout(this.layerId.name), self:getLayerLayout(this.layerId.region), self:getLayerLayout(this.layerId.transport)}) do
        for i, elem in ipairs(layout.content) do
            if not elem.userData or not elem.userData.params then goto continue end

            if elem.name and (elem.userData.params.showWhenZoomedIn or false) ~= isInZoomInMode and
                    (elem.userData.params.showWhenZoomedOut or false) ~= not isInZoomInMode then
                stuckedMarkers[elem.name] = elem.userData.params.layerId
                goto continue
            end

            if elem.userData and elem.userData.autoScale then
                local props = elem.userData.inContainer and elem.content[1].props or elem.props
                if props.text then
                    local tSizeVal = (elem.userData.scaleFunc or self.SCALE_FUNCTION.marker)(elem.userData.fontSize, self.zoom)
                    props.textSize = math.max(1, tSizeVal)
                    if props.size then
                        props.size = (elem.userData.scaleFunc or self.SCALE_FUNCTION.marker)(elem.userData.size, self.zoom)
                    end
                elseif props.resource then
                    props.size = (elem.userData.scaleFunc or self.SCALE_FUNCTION.marker)(elem.userData.size, self.zoom)
                end
            end

            ::continue::
        end
    end

    for id, layerId in pairs(stuckedMarkers) do
        self:removeMarker(id, layerId)
    end
end


function mapWidgetMeta:updateMarkers(force)
    setZoom(self, self.zoom, nil, force, true)
end


function mapWidgetMeta:refreshVisibleArea(skipPlayerTilesUpdate)
    local visibleRect = self:getVisibleMapRectInWorldCoordinates()

    if self._markerRectLimited.top < visibleRect.top or self._markerRectLimited.bottom > visibleRect.bottom or
            self._markerRectLimited.right < visibleRect.right or self._markerRectLimited.left > visibleRect.left then
        self:updateOnZoomMarkers()
        if not skipPlayerTilesUpdate then
            self._updatePlayerTiles = true
        end
    end
end


local function getMarkerCacheId(id, layerId)
    return id.."_"..tostring(layerId)
end



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
---@field useCache boolean? deprecated
---@field searchText string? lowercase
---@field searchLabel string?
---@field userData table?
---@field update boolean?

---@class advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params
---@field layerId integer
---@field id string?
---@field pos any in the game world
---@field text string
---@field events table?
---@field tooltipContent any
---@field fontSize number?
---@field size any util.vector2
---@field autoHeight boolean?
---@field color any util.color.rgb
---@field textShadow boolean?
---@field shadowColor any util.color.rgb
---@field textBackground boolean?
---@field textBackgroundColor any util.color.rgb
---@field textBackgroundAlpha number?
---@field anchor any util.vector2
---@field textAlignH any ui.ALIGNMENT
---@field textAlignV any ui.ALIGNMENT
---@field alpha number?
---@field visible boolean?
---@field showWhenZoomedIn boolean?
---@field showWhenZoomedOut boolean?
---@field scaleFunc (fun(size: any, zoom: number): number)?
---@field useCache boolean? deprecated
---@field searchText string? lowercase
---@field searchLabel string?
---@field userData table?
---@field update boolean?


---@param params advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
---@return string
local function getActiveMarkerId(params)
    return string.format("%s_%d", params.id or "", params.layerId or this.layerId.marker)
end


---@param self advancedWorldMap.ui.mapWidgetMeta
---@param params advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
---@param onlyInitialize boolean? if true, the marker will only be initialized and not added to the map. if false, it will be added if possible. If nil, it will be added anyway. 
---@return string? id
---@return integer? layerId
---@return advancedWorldMap.ui.mapElementMeta?
---@return any? layout
local function createMarker(self, params, onlyInitialize)
    if not params then params = {layerId = this.layerId.marker} end
    if not params.layerId then params.layerId = this.layerId.marker end

    local isLayerInteractive = params.layerId == this.layerId.marker

    if params.textBackground and (params.textBackgroundAlpha or 1) == 0 then
        params.textBackground = nil
    end

    local content = self:getLayerLayout(params.layerId).content

    local function updateZoomInOutDataParams(id, _params)
        local cId = self.zoomMarkersCellIdById[id]
        if cId then
            if self.zoomInMarkers[cId] and self.zoomInMarkers[cId][id] then
                self.zoomInMarkers[cId][id].params = _params
            end
            if self.zoomOutMarkers[cId] and self.zoomOutMarkers[cId][id] then
                self.zoomOutMarkers[cId][id].params = _params
            end
        end
    end

    if params.id and uiUtils.isExistsInContent(content, params.id) then
        local handler = content[params.id].userData.markerElement
        if params.update then
            updateZoomInOutDataParams(params.id, params)
            handler._elemLayout.userData.userData = params.userData
            handler._params = params
            handler:restoreLayout()
            params.update = nil
            eventSys.triggerEvent(eventSys.EVENT.onMapElementCreated, {mapWidget = self, marker = handler})
        end
        return params.id, params.layerId, handler, content[params.id]
    end

    local function addZoomInOutData(id, layout)
        if self.zoomMarkersCellIdById[id] then return end
        local cellId = layout.userData.cellId or cellLib.getCellIdByPos(params.pos)

        if params.showWhenZoomedIn then
            self.zoomInMarkers[cellId] = self.zoomInMarkers[cellId] or {}
            self.zoomInMarkers[cellId][id] = {
                id = id,
                params = params
            }
            self.zoomMarkersCellIdById[id] = cellId
            layout.userData.showWhenZoomedIn = true
            layout.userData.cellId = cellId
        end
        if params.showWhenZoomedOut then
            self.zoomOutMarkers[cellId] = self.zoomOutMarkers[cellId] or {}
            self.zoomOutMarkers[cellId][id] = {
                id = id,
                params = params
            }
            self.zoomMarkersCellIdById[id] = cellId
            layout.userData.showWhenZoomedOut = true
            layout.userData.cellId = cellId
        end
        self.activeZoomMarkers[getActiveMarkerId(params)] = {id, params.layerId, layout.userData.markerElement}
    end

    params.pos = params.pos or util.vector3(0, 0, 0)
    local relPos = self:getRelativePositionByWorldPosition(params.pos)

    local placeOnMap = onlyInitialize == nil or self.cellId ~= nil or
        onlyInitialize == false and self._markerRect and this.isPointInRegion(self._markerRect, params.pos.x, params.pos.y) or false

    if placeOnMap and params.id then
        ---@type string
        local id = params.id
        local cacheId = getMarkerCacheId(id, params.layerId)
        local cachedLayout = self._markerLayoutCache[cacheId]
        if cachedLayout then
            local handler = cachedLayout.userData.markerElement

            if params.update then
                updateZoomInOutDataParams(id, params)
                handler._params = params
                handler:restoreLayout()
                params.update = nil
            elseif cachedLayout.userData.forceChanged then
                handler:restoreLayout()
            end

            cachedLayout.props.relativePosition = relPos

            if eventSys.triggerEvent(
                        eventSys.EVENT.onMapElementCreate,
                        {mapWidget = self, marker = handler}
                    ) then
                return
            end

            if params.visible == false then
                self.hiddenElements[params.layerId][id] = cachedLayout
                eventSys.triggerEvent(eventSys.EVENT.onMapElementCreated, {mapWidget = self, marker = handler})
                return id, params.layerId, handler, cachedLayout
            end

            addZoomInOutData(id, cachedLayout)

            local props = cachedLayout.userData.inContainer and cachedLayout.content[1].props or cachedLayout.props
            if props.textSize then
                props.textSize = (cachedLayout.userData.scaleFunc or self.SCALE_FUNCTION.marker)(cachedLayout.userData.fontSize, self.zoom)
            end
            if props.size then
                props.size = (cachedLayout.userData.scaleFunc or self.SCALE_FUNCTION.marker)(cachedLayout.userData.size, self.zoom)
            end

            if self.inActiveMode then
                cachedLayout.events = cachedLayout.userData._events or cachedLayout.events
                cachedLayout.userData._events = nil
            else
                cachedLayout.userData._events = cachedLayout.events or cachedLayout.userData._events
                cachedLayout.events = nil
            end

            local res = uiUtils.safeAddToContent(content, cachedLayout)
            if res then
                eventSys.triggerEvent(eventSys.EVENT.onMapElementCreated, {mapWidget = self, marker = handler})
                return id, params.layerId, handler, cachedLayout
            else
                return
            end
        end
    end

    local fontSize = params.fontSize or 18
    local color = params.color or config.data.ui.defaultColor
    local alpha = params.alpha
    local anchor = params.anchor or util.vector2(0.5, 0.5)

    local size = params.size
    local texture = params.texture

    local events = params.events or {}

    params.id = params.id or tostring(self:getUniqueId())
    ---@type string
    local markerName = params.id

    local layoutEvents = isLayerInteractive and self.markerEvents or nil

    local layout
    layout = {
        type = params.text and (params.autoHeight and ui.TYPE.TextEdit or ui.TYPE.Text) or ui.TYPE.Image,
        name = markerName,
        props = {
            text = params.text,
            textSize = params.text and fontSize and (params.scaleFunc or self.SCALE_FUNCTION.marker)(fontSize, self.zoom),
            autoSize = params.autoHeight and true or nil,
            anchor = anchor,
            relativePosition = relPos,
            textColor = params.text and color or nil,
            textShadow = params.text and params.textShadow or nil,
            textShadowColor = params.text and params.shadowColor or nil,
            visible = params.visible,
            alpha = alpha,
            resource = texture,
            size = size and (params.scaleFunc or self.SCALE_FUNCTION.marker)(size, self.zoom),
            color = params.texture and color or nil,
            propagateEvents = false,
            textAlignH = params.textAlignH,
            textAlignV = params.textAlignV,
            multiline = params.autoHeight and true or nil,
            wordWrap = params.autoHeight and true or nil,
            readOnly = params.autoHeight and true or nil,
        },
        userData = {
            scaleFunc = params.scaleFunc,
            autoScale = true,
            fontSize = params.text and fontSize,
            size = size,
            params = params,
            events = events,
            userData = params.userData,
            cellId = self.cellId,
            pressed = {},
            movedDistance = 0,
            inContainer = params.text and params.textBackground,
            onMouseWheel = isLayerInteractive and self.mouseWheelEvent or nil,
            _events = not self.inActiveMode and layoutEvents or nil,
        },
        events = self.inActiveMode and layoutEvents or nil,
    }

    local marker
    if layout.userData.inContainer then
        layout.props.anchor = nil
        layout.props.relativePosition = nil
        layout.props.alpha = nil
        layout.props.visible = nil
        local ev = layout.events

        local bgColor = params.textBackgroundColor or config.data.ui.backgroundColor
        local bgAlpha = params.textBackgroundAlpha
        local templateId = string.format("%s_%s", bgColor, bgAlpha)
        local template = self._markerTemplateCache[templateId]
        if not template then
            template = {
                type = ui.TYPE.Container,
                content = ui.content{
                    {
                        type = ui.TYPE.Image,
                        props = {
                            resource = uiUtils.whiteTexture,
                            color = bgColor,
                            relativeSize = util.vector2(1, 1),
                            alpha = bgAlpha,
                        }
                    },
                }
            }
            self._markerTemplateCache[templateId] = template
        end

        marker = {
            template = template,
            name = layout.name,
            props = {
                anchor = anchor,
                relativePosition = relPos,
                visible = params.visible,
                alpha = alpha,
            },
            userData = layout.userData,
            events = ev,
            content = ui.content{
                layout,
            }
        }
        layout.userData.container = marker
    else
        marker = layout
    end

    -- Do not cache built-in markers
    if onlyInitialize ~= nil then
        self._markerLayoutCache[getMarkerCacheId(markerName, params.layerId)] = marker
    end

    local markerELement = mapElement.new(self, markerName, params.layerId, params, layout)
    marker.userData.markerElement = markerELement

    addZoomInOutData(markerName, marker)

    eventSys.triggerEvent(eventSys.EVENT.onMapElementInitialized, {mapWidget = self, marker = markerELement})

    if params.update then params.update = nil end

    if not placeOnMap then
        return markerName, params.layerId, markerELement, marker
    end

    if eventSys.triggerEvent(eventSys.EVENT.onMapElementCreate, {mapWidget = self, marker = markerELement}) then
        return
    end

    if params.visible == false then
        self.hiddenElements[params.layerId][markerName] = marker
        eventSys.triggerEvent(eventSys.EVENT.onMapElementCreated, {mapWidget = self, marker = markerELement})
        return markerName, params.layerId, markerELement, marker
    end

    if uiUtils.safeAddToContent(content, marker) then
        eventSys.triggerEvent(eventSys.EVENT.onMapElementCreated, {mapWidget = self, marker = markerELement})
    else
        return
    end

    return markerName, params.layerId, markerELement, marker
end


---@param params advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
---@return advancedWorldMap.ui.mapElementMeta?
function mapWidgetMeta:createImageMarker(params)
    if not params.texture then return end
    if not params.showWhenZoomedIn and not params.showWhenZoomedOut then
        params.showWhenZoomedIn = true
        params.showWhenZoomedOut = true
    end

    local isInZoomInMode = self:isInZoomInMode()
    local onlyInitializeParam = isInZoomInMode and not params.showWhenZoomedIn or
        not isInZoomInMode and not params.showWhenZoomedOut

    local id, layerId, element = createMarker(self, params, onlyInitializeParam)
    return element
end

---@param params advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params
---@return advancedWorldMap.ui.mapElementMeta?
function mapWidgetMeta:createTextMarker(params)
    if not params.text then return end
    if not params.showWhenZoomedIn and not params.showWhenZoomedOut then
        params.showWhenZoomedIn = true
        params.showWhenZoomedOut = true
    end
    if params.autoHeight == true and params.layerId == this.layerId.marker then
        log("Not allowed to create autoHeight text marker in 'marker' layer")
        return
    end

    local isInZoomInMode = self:isInZoomInMode()
    local onlyInitializeParam = isInZoomInMode and not params.showWhenZoomedIn or
        not isInZoomInMode and not params.showWhenZoomedOut

    local id, layerId, element = createMarker(self, params, onlyInitializeParam)
    return element
end


---@param self advancedWorldMap.ui.mapWidgetMeta
local function removeMarker(self, id, layer)
    if not id or not layer then return false end
    local content = self:getLayerLayout(layer).content

    if self.hiddenElements[layer][id] then
        self.hiddenElements[layer][id] = nil
        return true
    end

    return uiUtils.removeFromContent(content, id) ~= nil
end


---@return boolean removedFromMap
function mapWidgetMeta:removeMarker(id, layer)
    if not id then return false end
    local removedFromMap = removeMarker(self, id, layer)

    local cellId = self.zoomMarkersCellIdById[id]
    if cellId then
        if self.zoomInMarkers[cellId] then
             self.zoomInMarkers[cellId][id] = nil
        end
        if self.zoomOutMarkers[cellId] then
            self.zoomOutMarkers[cellId][id] = nil
        end
        self.zoomMarkersCellIdById[id] = nil
    end

    local cacheId = getMarkerCacheId(id, layer)
    if self._markerLayoutCache[cacheId] then
        self._markerLayoutCache[cacheId] = nil
    end

    if self.hiddenElements[layer][id] then
        self.hiddenElements[layer][id] = nil
    end

    return removedFromMap
end


function mapWidgetMeta:hasMarker(id)
    return self.zoomMarkersCellIdById[id] ~= nil
end


function mapWidgetMeta:setElementVisibility(id, layer, visible)
    if not id or not layer then return false end
    local content = self:getLayerLayout(layer).content

    if visible then
        if self.hiddenElements[layer][id] then
            local marker = self.hiddenElements[layer][id]
            self.hiddenElements[layer][id] = nil

            if marker.props.textSize then
                marker.props.textSize = (marker.userData.scaleFunc or self.SCALE_FUNCTION.marker)(marker.userData.fontSize, self.zoom)
            end
            if marker.props.size then
                marker.props.size = (marker.userData.scaleFunc or self.SCALE_FUNCTION.marker)(marker.userData.size, self.zoom)
            end

            return uiUtils.safeAddToContent(content, marker) ~= nil
        end
    else
        local element = uiUtils.getFromContent(content, id)
        if element then
            self.hiddenElements[layer][id] = element
            return uiUtils.removeFromContent(content, id) ~= nil
        end
    end

    return false
end


---@param self advancedWorldMap.ui.mapWidgetMeta
---@param params advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
local function tryCreateActiveMarker(self, params, preloadOnly)
    local id = getActiveMarkerId(params)

    local isCreated = self.activeZoomMarkers[id] ~= nil
    local pos = params.pos or util.vector2(0, 0)
    local placeOnMap = not isCreated or self.cellId ~= nil or
        (self._markerRect and this.isPointInRegion(self._markerRect, pos.x, pos.y)) or false

    if placeOnMap then
        local mDt = {createMarker(self, params, preloadOnly)}
        if mDt[1] then
            self.activeZoomMarkers[id] = mDt
        end
    end
end


---@param region advancedWorldMap.ui.mapWidget.region
function mapWidgetMeta:createZoomOutMarkers(region, preloadOnly, force)
    if not force and self.onZoomMarkersRect and this.compareRegions(self.onZoomMarkersRect, region) then
        return
    end

    local minGridX = math.floor(region.left / 8192)
    local maxGridX = math.ceil(region.right / 8192)
    local minGridY = math.floor(region.bottom / 8192)
    local maxGridY = math.ceil(region.top / 8192)
    for x = minGridX - 1, maxGridX + 1 do
        for y = minGridY - 1, maxGridY + 1 do
            local cellId = cellLib.getCellIdByGrid(x, y)

            for _, dt in pairs(self.zoomOutMarkers[cellId] or {}) do
                tryCreateActiveMarker(self, dt.params, preloadOnly)
            end
        end
    end

    if preloadOnly then return end

    eventSys.triggerEvent(eventSys.EVENT.onZoomMarkersUpdated, {mapWidget = self, region = region})

    self.onZoomMarkersRect = region
end



---@param region advancedWorldMap.ui.mapWidget.region
function mapWidgetMeta:createZoomInMarkers(region, preloadOnly, force)

    if self.cellId then
        for _, dt in pairs(self.zoomInMarkers[self.cellId] or {}) do
            tryCreateActiveMarker(self, dt.params, preloadOnly)
        end

        eventSys.triggerEvent(eventSys.EVENT.onZoomMarkersUpdated, {mapWidget = self, region = region})
    else
        if not force and self.onZoomMarkersRect and this.compareRegions(self.onZoomMarkersRect, region) then
            return
        end

        local minGridX = math.floor(region.left / 8192)
        local maxGridX = math.floor(region.right / 8192)
        local minGridY = math.floor(region.bottom / 8192)
        local maxGridY = math.floor(region.top / 8192)

        for x = minGridX, maxGridX do
            for y = minGridY, maxGridY do
                local cellId = commonData.exteriorCellIdFormat:format(x, y)

                for _, dt in pairs(self.zoomInMarkers[cellId] or {}) do
                    local pos = dt.params.pos
                    if this.isPointInRegion(region, pos.x, pos.y) then
                        tryCreateActiveMarker(self, dt.params, preloadOnly)
                    end
                end

            end
        end

        if preloadOnly then return end

        eventSys.triggerEvent(eventSys.EVENT.onZoomMarkersUpdated, {mapWidget = self, region = region})

        self.onZoomMarkersRect = region
    end
end


---@param allowRect advancedWorldMap.ui.mapWidget.region?
function mapWidgetMeta:removeOnZoomMarkers(allowRect)
    if allowRect then
        for i, dt in pairs(self.activeZoomMarkers) do
            local markerPos = dt[3]._params.pos or {x = 0, y = 0}
            if not this.isPointInRegion(allowRect, markerPos.x, markerPos.y) then
                removeMarker(self, dt[1], dt[2])
                self.activeZoomMarkers[i] = nil
                eventSys.triggerEvent(eventSys.EVENT.onMapElementRemoved, {mapWidget = self, marker = dt[3]})
            end
        end
    else
        for i, dt in pairs(self.activeZoomMarkers) do
            removeMarker(self, dt[1], dt[2])
            self.activeZoomMarkers[i] = nil
            eventSys.triggerEvent(eventSys.EVENT.onMapElementRemoved, {mapWidget = self, marker = dt[3]})
        end
    end
end


function mapWidgetMeta:removeGroundTextures()
    if self._groundTexturesCoroutine and coroutine.status(self._groundTexturesCoroutine) ~= "dead" then
        self._coroutineCancelFlags[self._groundTexturesCoroutine] = true
        coroutine.resume(self._groundTexturesCoroutine)
        self._groundTexturesCoroutine = nil
    end

    local mapLayoutContent = self:getMapLayout().content
    for i = #mapLayoutContent, 2, -1 do
        uiUtils.removeFromContent(mapLayoutContent, i)
    end
end


---@param region advancedWorldMap.ui.mapWidget.region
function mapWidgetMeta:placeGroundTextures(region)
    self:removeGroundTextures()

    if eventSys.triggerEvent(eventSys.EVENT.onGroundTexturesPlace, {mapWidget = self, region = region}) then
        return
    end

    if self.localCellInfo then
        if self.cellStatics then
            local cellSize = self.mapInfo.cellSize or 8192
            for _, dt in pairs(self.cellStatics) do
                createMarker(self, {
                    layerId = this.layerId.map,
                    texture = uiUtils.whiteTexture,
                    color = config.data.ui.defaultTextureColor,
                    pos = util.vector2(dt[1], dt[2]),
                    size = util.vector2(dt[3] / cellSize * self.mapInfo.pixelsPerCell + 1, dt[4] / cellSize * self.mapInfo.pixelsPerCell + 1),
                    scaleFunc = this.scaleFunction.linear,
                    anchor = util.vector2(0.5, 0.5)
                })
            end

            return
        end

        local mapLayout = self:getMapLayout()

        -- Version 2 uses single texture for the whole cell
        if self.localCellInfo.v == 2 then
            local texture = (self.mapTexture[1] or {})[1]
            if not texture then return end

            local cellSize = self.mapInfo.cellSize or 8192
            local startingPos = self:getAbsolutePositionByWorldPosition(
                util.vector2(
                    self.mapInfo.gridX.min * cellSize,
                    self.mapInfo.gridY.max * cellSize
                ),
                true
            )
            local side = util.round(self.mapInfo.pixelsPerCell * self.zoom)
            local size = util.vector2(self.localCellInfo.wT * side, self.localCellInfo.hT * side)

            mapLayout.content:add{
                type = ui.TYPE.Image,
                props = {
                    resource = texture,
                    size = size,
                    position = startingPos,
                }
            }


        -- Version 1 uses multiple textures for the cell
        elseif self.localCellInfo.height then
            local cellSize = self.mapInfo.cellSize or 8192
            local startingPos = self:getAbsolutePositionByWorldPosition(
                util.vector2(
                    self.mapInfo.gridX.min * cellSize,
                    self.mapInfo.gridY.min * cellSize
                ),
                true
            )
            local tileHeight = util.round(self.mapInfo.pixelsPerCell * self.zoom)
            local tileSize = util.vector2(tileHeight, tileHeight)
            for y = 1, self.localCellInfo.height do
                for x = 1, self.localCellInfo.width do
                    local texture = (self.mapTexture[y] or {})[x]
                    if not texture then goto continue end

                    local pos = util.vector2(startingPos.x + tileHeight * (x - 1), startingPos.y - tileHeight * (y - 1))

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

    else
        local minGridX = math.floor(region.left / 8192)
        local maxGridX = math.ceil(region.right / 8192)
        local minGridY = math.floor(region.bottom / 8192)
        local maxGridY = math.ceil(region.top / 8192)

        local mapLayout = self:getMapLayout()

        local function placeTiles(func, startPos, tileFullHeight, gridTileMinX, gridTileMaxX, gridTileMinY, gridTileMaxY, alpha)
            -- tileFullHeight = tileFullHeight + (tileFullHeight % 2)

            local xP = startPos.x + tileFullHeight * -2
            for x = -1, gridTileMaxX - gridTileMinX do
                local lxP = xP
                xP = startPos.x + tileFullHeight * x
                local xPr = math.floor(xP)
                local xS = math.ceil(xP) - math.floor(lxP)

                local yP = startPos.y - tileFullHeight * -2
                for y = -1, gridTileMaxY - gridTileMinY do
                    local texture = func(gridTileMinX + x, gridTileMinY + y)

                    local lyP = yP
                    yP = startPos.y - tileFullHeight * y
                    local yPr = math.floor(yP)
                    local yS = math.ceil(lyP) - math.floor(yP)
                    local pos = util.vector2(xPr, yPr)
                    local sz = util.vector2(xS, yS)

                    if not texture then goto continue end

                    mapLayout.content:add{
                        type = ui.TYPE.Image,
                        props = {
                            resource = texture,
                            size = sz,
                            position = pos,
                            anchor = util.vector2(0, 1),
                            alpha = alpha,
                        }
                    }

                    ::continue::
                end
            end
        end


        if self.mapInfo and (self.mapInfo.version == 2 or self.mapInfo.version == 3) then
            local tileSize
            local tileGridSize
            local tileCoordSize
            local gridTileMinX
            local gridTileMaxX
            local gridTileMinY
            local gridTileMaxY
            local startPos

            local function calcVars(mapInfo)
                tileSize = mapInfo.tileSize or (mapInfo.pixelsPerCell * 16)
                tileGridSize = tileSize / mapInfo.pixelsPerCell
                tileCoordSize = tileGridSize * 8192
                gridTileMinX = math.floor(minGridX < 0 and (minGridX + 1) / tileGridSize - 1 or minGridX / tileGridSize)
                gridTileMaxX = math.ceil(maxGridX < 0 and (maxGridX + 1) / tileGridSize - 1 or maxGridX / tileGridSize)
                gridTileMinY = math.floor(minGridY < 0 and (minGridY + 1) / tileGridSize - 1 or minGridY / tileGridSize)
                gridTileMaxY = math.ceil(maxGridY < 0 and (maxGridY + 1) / tileGridSize - 1 or maxGridY / tileGridSize)

                startPos = self:getAbsolutePositionByWorldPosition(
                    util.vector2(tileCoordSize * gridTileMinX, tileCoordSize * gridTileMinY - 8192)
                )
                startPos = util.vector2(math.floor(startPos.x), math.floor(startPos.y))
            end

            calcVars(self.mapInfo)

            local tileFullHeight = tileSize * self.zoom

            placeTiles(mapTextureHandler.getWorldMapTextureV2, startPos, tileFullHeight,
                gridTileMinX, gridTileMaxX, gridTileMinY, gridTileMaxY)

            ---@type advancedWorldMap.mapImageInfo?
            local altMapInfo = config.data.data.altExMapInfo
            if altMapInfo then
                calcVars(altMapInfo)
                local tileFullHeight = math.floor(tileSize * self.zoom * self._altTexturePxDiffMul)

                placeTiles(mapTextureHandler.getWorldMapTextureV2_alt, startPos, tileFullHeight,
                    gridTileMinX, gridTileMaxX, gridTileMinY, gridTileMaxY, config.data.data.altExMapAlpha * 0.01)
            end
        end

        local isZoomOut = not self:isInZoomInMode()
        if isZoomOut and not config.data.legend.visitedCellsOnWorldMap then return end


        local startPos = self:getAbsolutePositionByWorldPosition(util.vector2(8192 * minGridX, 8192 * minGridY))
        startPos = util.vector2(math.floor(startPos.x), math.floor(startPos.y))
        local tileFullHeight = self.mapInfo.pixelsPerCell * self.zoom

        local mapLayout = self:getMapLayout()
        local queue = {}

        local xP = startPos.x + tileFullHeight * -2
        for x = -1, maxGridX - minGridX do
            local lxP = xP
            xP = startPos.x + tileFullHeight * x
            local xPr = math.floor(xP)
            local xS = xPr - math.floor(lxP) + 1

            local yP = startPos.y - tileFullHeight * -2
            for y = -1, maxGridY - minGridY do
                local grx = minGridX + x
                local gry = minGridY + y + 1

                local cellId = cellLib.getCellIdByGrid(grx, gry)
                local isValidCell = cellId and (mapDataHandler.cellNameById[cellId] or mapDataHandler.validCellsWithoutName[cellId])
                local isValid = isValidCell and (
                    not isZoomOut and (not config.data.tileset.onlyDiscovered or discoveredLocs.isDiscovered(cellId)) or
                    isZoomOut and config.data.legend.visitedCellsOnWorldMap and discoveredLocs.isVisited(cellId)
                )

                local lyP = yP
                yP = startPos.y - tileFullHeight * y
                local yPr = math.floor(yP)
                local yS = math.floor(lyP) - yPr + 1
                local pos = util.vector2(xPr, yPr)
                local sz = util.vector2(xS, yS)

                if not isValid then goto continue end

                if mapTextureHandler.isLocalWorldMapTextureInCache(grx, gry) then
                    local texture = mapTextureHandler.getLocalMapTexture(grx, gry)
                    if texture then
                        mapLayout.content:add{
                            type = ui.TYPE.Image,
                            props = {
                                resource = texture,
                                size = sz,
                                position = pos,
                                anchor = util.vector2(0, 1)
                            }
                        }
                    end
                else
                    table.insert(queue, {grx = grx, gry = gry, pos = pos, sz = sz})
                end

                ::continue::
            end
        end

        local maxTilesPerFrame = isZoomOut and 400 or 6
        local function updateTiles()
            local cnt = 0
            for i, dt in pairs(queue) do
                local texture = mapTextureHandler.getLocalMapTexture(dt.grx, dt.gry)
                if not texture then goto continue end

                mapLayout.content:add{
                    type = ui.TYPE.Image,
                    props = {
                        resource = texture,
                        size = dt.sz,
                        position = dt.pos,
                        anchor = util.vector2(0, 1)
                    }
                }
                cnt = cnt + 1
                if cnt % maxTilesPerFrame == 0 then
                    coroutine.yield()
                end
                ::continue::
            end
        end

        local co = coroutine.create(updateTiles)
        self._groundTexturesCoroutine = co
        local function runCo()
            if self._coroutineCancelFlags[co] then
                self._coroutineCancelFlags[co] = nil
                return
            end
            if coroutine.status(co) ~= "dead" then
                coroutine.resume(co)
                self:update()
                realTimer.newTimer(0, runCo)
            else
                self._coroutineCancelFlags[co] = nil
            end
        end
        runCo()
    end
end


---@param self advancedWorldMap.ui.mapWidgetMeta
---@param mapInfo advancedWorldMap.mapImageInfo?
---@param texture string|any?
local function getWorldMapTextureLayout(self, mapInfo, texture, oldMapLayout)
    if not mapInfo then
        mapInfo = {
            gridX = {min = 0, max = 0},
            gridY =  {min = 0, max = 0},
            height = 32,
            pixelsPerCell = 32,
            time = 0,
            version = 0,
            width = 32,
            file = "",
        }
    end

    self.mapTexture = texture
    self.mapInfo = mapInfo
    self.eScale = mapInfo.pixelsPerCell / 32

    local padding = 1

    padding = math.max(padding, math.max(0, mapDataHandler.grid.max.x - self.mapInfo.gridX.max) +
        math.max(0, self.mapInfo.gridX.min - mapDataHandler.grid.min.x))
    padding = math.max(padding, math.max(0, mapDataHandler.grid.max.y - self.mapInfo.gridY.max) +
        math.max(0, self.mapInfo.gridY.min - mapDataHandler.grid.min.y))

    padding = padding * self.mapInfo.pixelsPerCell

    self.borderPadding = util.vector2(padding, padding)
    self.displayMapSize = util.vector2(self.mapInfo.width + padding * 2, self.mapInfo.height + padding * 2)

    if oldMapLayout then
        uiUtils.clearContent(oldMapLayout.content)
    end

    local mapLayout = oldMapLayout or {
        type = ui.TYPE.Widget,
        props = {
            position = util.vector2(0, 0),
            relativeSize = util.vector2(1, 1),
        },
        userData = {},
        content = ui.content {},
    }

    if texture then

        mapLayout.content:add{
            type = ui.TYPE.Image,
            props = {
                resource = texture,
                relativePosition = util.vector2(self.borderPadding.x / self.displayMapSize.x, self.borderPadding.y / self.displayMapSize.y),
                relativeSize = util.vector2(self.mapInfo.width / self.displayMapSize.x, self.mapInfo.height / self.displayMapSize.y),
            }
        }

    elseif mapInfo.version == 2 or mapInfo.version == 3 then
        mapLayout.content:add{
            type = ui.TYPE.Image,
            props = {
                resource = uiUtils.whiteTexture,
                relativePosition = util.vector2(self.borderPadding.x / self.displayMapSize.x, self.borderPadding.y / self.displayMapSize.y),
                relativeSize = util.vector2(self.mapInfo.width / self.displayMapSize.x, self.mapInfo.height / self.displayMapSize.y),
                color = mapInfo.bColor and util.color.rgb(mapInfo.bColor[1], mapInfo.bColor[2], mapInfo.bColor[3]) or commonData.mapWaterColor
            }
        }

    else
        local pixelsPerCell = self.mapInfo.pixelsPerCell

        local layout = {
            type = ui.TYPE.Widget,
            props = {
                relativePosition = util.vector2(0, 0),
                relativeSize = util.vector2(1, 1),
            },
            userData = {},
            content = ui.content {},
        }

        for i, dt in pairs(mapDataHandler.worldMapTileRectangles or {}) do
            local widthHeight = util.vector2(dt[3] - dt[1] + 1, dt[4] - dt[2] + 1)
            local pos = util.vector2(dt[1] - 0.125, dt[2] - 0.125) * 8192
            local relSize = util.vector2(
                ((widthHeight.x + 0.25) * pixelsPerCell) / self.displayMapSize.x,
                ((widthHeight.y + 0.25) * pixelsPerCell) / self.displayMapSize.y
            )

            local lay = {
                type = ui.TYPE.Image,
                props = {
                    resource = uiUtils.whiteTexture,
                    color = config.data.ui.defaultTextureColor,
                    anchor = util.vector2(0, 1),
                    relativePosition = self:getRelativePositionByWorldPosition(pos),
                    relativeSize = relSize,
                }
            }
            layout.content:add(lay)
        end

        mapLayout.content:add(layout)
    end

    return mapLayout
end


---@param texture string|any?
---@param mapInfo advancedWorldMap.mapImageInfo?
function mapWidgetMeta:updateWorldMapTexture(texture, mapInfo)
    if self.cellId then return end
    if not mapInfo then mapInfo = self.mapInfo end

    if type(texture) == "string" then
        texture = ui.texture{ path = texture }
    end
    getWorldMapTextureLayout(self, mapInfo, texture, self:getLayerLayout(this.layerId.map))
    self:setZoom(self.zoom, nil, nil, true)
end


---@param focusOnPlayer boolean?
---@return boolean
function mapWidgetMeta:updatePlayerMarker(focusOnPlayer, forceUpdate)
    self:refreshVisibleArea(true)

    local lay = self:getPlayerLayout()
    if lay.props.visible == false and not focusOnPlayer then return false end

    local playerMarkerLayout = lay.content[1]
    local playerCell = playerRef.cell

    if self.cellId and self.cellId ~= (not playerCell.isExterior and playerRef.cell.id) then
        local visible = playerMarkerLayout.props.visible
        playerMarkerLayout.props.visible = false
        return visible ~= false
    else
        playerMarkerLayout.props.visible = self._playerMarkerVisible ~= false
    end

    if self._playerMarkerVisible == false and not focusOnPlayer then return false end

    local mapLayerPosition = self:getMapLayersLayout().props.position

    local pos = self.cellId and playerRef.position or playerPos.gexExteriorPos()
    local dist = (playerMarkerLayout.userData.lastPos - pos):length()

    local yaw = playerRef.rotation:getYaw()
    local lastYaw = playerMarkerLayout.userData.lastYaw

    if not forceUpdate
            and dist < (8192 / (self.mapInfo.pixelsPerCell * self.zoom * self.eScale * 2))
            and (math.abs(yaw - lastYaw) < 0.1) then
        return false
    end

    local playerRelPos = self:getRelativePositionByWorldPosition(pos)
    playerMarkerLayout.props.relativePosition = playerRelPos
    playerMarkerLayout.props.resource = playerMarker.getTexture(self.northDirectionAngle, yaw) or playerMarkerTexture
    if dist > 4096 or commonData.distance2D(playerMarkerLayout.userData.lastLayPos, mapLayerPosition) > 1000 then
        self._updatePlayerTiles = true
    end
    playerMarkerLayout.userData.lastPos = pos
    playerMarkerLayout.userData.lastYaw = yaw
    playerMarkerLayout.userData.lastLayPos = mapLayerPosition

    if focusOnPlayer then
        if self._updatePlayerTiles then
            self:setZoom(self.zoom, playerRelPos, nil, true)
            self._updatePlayerTiles = false
        else
            self:focusOnWorldPosition(pos)
        end
    end

    return true
end


function mapWidgetMeta:setUpdateFunction(func)
    self.update = func
    self.layout.userData.lastDraggedMousePos = nil
end


function mapWidgetMeta:openRightMouseMenu()
    local menu = self.layout.userData.contextMenu
    if menu and menu.layout then
        menu:destroy()
        self.layout.userData.contextMenu = nil
    end

    if eventSys.isContainsHandler(eventSys.EVENT["onRightMouseMenu"]) then
        local layersLayout = self.layout.content[2]
        uiUtils.removeFromContent(layersLayout.content, commonData.rightClickMenuId)

        local pos = self:getScreenPositionOfCursor()
        local lay = {
            layer = commonData.messageLayer,
            name = commonData.rightClickMenuId,
            type = ui.TYPE.Flex,
            props = {
                autoSize = true,
                position = pos,
                anchor = util.vector2(0, 0),
                propagateEvents = false,
            },
            content = ui.content{

            },
        }
        local layContent = lay.content
        eventSys.triggerEvent(eventSys.EVENT["onRightMouseMenu"], {
            mapWidget = self,
            relPos = self:getRelativePositionOfCursor(),
            content = layContent,
            marker = self.layout.userData.lastMarkerElement,
        })

        if #layContent > 0 then
            self.layout.userData.contextMenu = ui.create(lay)
        end
    end
end


function mapWidgetMeta:closeRightMouseMenu()
    local menu = self.layout.userData.contextMenu
    if not menu or not menu.layout then return end
    menu:destroy()
    self.layout.userData.contextMenu = nil
end


local function getDefaultLayerLayout()
    return {
        type = ui.TYPE.Widget,
        props = {
            position = util.vector2(0, 0),
            relativeSize = util.vector2(1, 1),
            visible = true,
        },
        userData = {},
        content = ui.content {

        },
    }
end


function mapWidgetMeta:setLayerVisibility(layerId, visible)
    local layout = self:getLayerLayout(layerId)

    if not layout then return false end

    layout.props.visible = visible
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


---@param self advancedWorldMap.ui.mapWidgetMeta
local function getMapBackgroundColor(self)
    if self.cellId then return commonData.mapInteriorBackgroundColor end
    if self.mapInfo and self.mapInfo.bColor then
        local bCol = self.mapInfo.bColor
        return util.color.rgb(bCol[1] or 1, bCol[2] or 1, bCol[3] or 1)
    else
        return commonData.mapWaterColor
    end
end


function mapWidgetMeta:setMapBackgroundColor(color)
    if not self.layout then return end
    self.layout.content[1].props.color = color
end


---@param visible boolean
---@return boolean changed
function mapWidgetMeta:setPlayerMarkerVisibility(visible)
    local lay = self:getPlayerLayout()

    local playerMarkerLayout = lay.content[1]
    local playerCell = playerRef.cell
    local oldState = playerMarkerLayout.props.visible

   if self.cellId and self.cellId ~= (not playerCell.isExterior and playerRef.cell.id) then
        playerMarkerLayout.props.visible = false
        return oldState ~= false
    else
        self._playerMarkerVisible = visible
        playerMarkerLayout.props.visible = visible
        return oldState ~= visible
    end
end

function mapWidgetMeta:getPlayerMarkerVisibility()
    local lay = self:getPlayerLayout()
    return lay.content[1].props.visible ~= false
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


---@return table<integer, advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params|advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params>
function mapWidgetMeta:getRegisteredMarkers()
    local markers = {}
    for _, dt in pairs(self.zoomInMarkers) do
        for _, m in pairs(dt) do
            if m.params then
                table.insert(markers, m.params)
            end
        end
    end
    for _, dt in pairs(self.zoomOutMarkers) do
        for _, m in pairs(dt) do
            if m.params then
                table.insert(markers, m.params)
            end
        end
    end
    return markers
end


function mapWidgetMeta:isInFocus()
    return self.layout.userData.inFocus == true
end


function mapWidgetMeta:isInActiveMode()
    return self.inActiveMode
end


function mapWidgetMeta:setInActiveMode(active)
    local modeChanged = self.inActiveMode ~= active
    self.inActiveMode = active

    if modeChanged then
        for _, mrk in pairs(self:getActiveMarkers()) do
            local userData = mrk._elemLayout.userData
            if not userData then goto continue end

            if active then
                mrk._container.events = mrk._container.userData._events or mrk._container.events
                mrk._container.userData._events = nil
            else
                mrk._container.userData._events = mrk._container.events or mrk._container.userData._events
                mrk._container.events = nil
            end

            ::continue::
        end
    end

    this.destroyPlayerMarkerMenu()
    if not active then
        self.layout.content[2].content[self.LAYER.player] = getDefaultLayerLayout()

        if not ui.layers.indexOf(commonData.playerMarkerLayer) then
            ui.layers.insertAfter("Windows", commonData.playerMarkerLayer, { interactive = false })
        end

        this.playerMarkerMenu = ui.create{
            type = ui.TYPE.Widget,
            layer = commonData.playerMarkerLayer,
            props = {
                position = self.screenPosition,
                size = self.layout.props.size,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Widget,
                    props = self.layout.content[2].props,
                    content = ui.content {
                        self:getPlayerLayout()
                    }
                },
            }
        }
    else
        self.layout.content[2].content[self.LAYER.player] = self.layers[self.LAYER.player]
    end
end


function mapWidgetMeta:isValid()
    return not self.invalid ---@diagnostic disable-line: undefined-field
end


---@class advancedWorldMap.ui.mapWidget.params
---@field size any
---@field fontSize integer?
---@field position any?
---@field relativePosition any?
---@field anchor any?
---@field cellId string?
---@field updateFunc function
---@field screenPosition any?
---@field zoom number?

---@param params advancedWorldMap.ui.mapWidget.params
---@return table?
---@return advancedWorldMap.ui.mapWidgetMeta?
function this.new(params)

    this.destroyPlayerMarkerMenu()

    params.fontSize = params.fontSize or 18

    ---@class advancedWorldMap.ui.mapWidgetMeta
    local meta = setmetatable({}, mapWidgetMeta)

    meta.params = params
    meta.userData = {}
    meta.cellId = params.cellId
    ---@type number[][] {x, y, width, height}
    meta.cellStatics = nil

    meta._markerLayoutCache = {}
    meta._markerTemplateCache = {}
    meta._coroutineCancelFlags = {}

    meta.screenPosition = params.screenPosition or util.vector2(0, 0)

    meta.uiScale = uiUtils.getUIScale()
    meta.uiScaleMul = math.sqrt(1 / meta.uiScale)

    meta.zoom = params.zoom or 1
    meta.maxZoom = meta.zoom
    meta.minZoom = meta.zoom

    meta.inActiveMode = true

    meta.SCALE_FUNCTION = {
        linear = function(size, zoom)
            return size * (zoom * meta.eScale)
        end,

        marker = function(size, zoom)
            zoom = zoom * meta.eScale
            return size * math.sqrt(math.sqrt(zoom)) * meta.uiScaleMul
        end,

        playerMarker = function(size, zoom)
            if zoom < 1 then
                return size * math.sqrt(zoom) * meta.uiScaleMul
            end
            return size
        end
    }

    local mapLayout

    if params.cellId then
        local localCellInfo = mapTextureHandler.getLocalCellInfo(params.cellId)
        if not localCellInfo.oX and not localCellInfo.mX then
            localCellInfo = {
                height = 20,
                width = 20,
                mX = 5120,
                mY = -5120,
                nA = 0,
            }
            core.sendGlobalEvent("AdvWMap:getMapStatics", {cellId = params.cellId, player = playerRef.object})
        end

        local mapTextures = mapTextureHandler.getLocalCellMapTextures(params.cellId)
        if not mapTextures then mapTextures = {} end

        local tScale = localCellInfo.tSc or 1
        local wT = localCellInfo.wT or localCellInfo.width
        local hT = localCellInfo.hT or localCellInfo.height

        local width = wT * 32
        local height = hT * 32

        local v2TileSize = (localCellInfo.tS or 256)

        local mapInfo = {
            cellSize = 8192 / tScale,
            width = width,
            height = height,
            pixelsPerCell = 32,
            gridX = {
                min = localCellInfo.oX and -localCellInfo.oX / v2TileSize or -localCellInfo.mX / 512,
                max = (localCellInfo.oX and -localCellInfo.oX / v2TileSize or -localCellInfo.mX / 512) + wT - 1,
            },
            gridY = {
                min = localCellInfo.oY and -localCellInfo.oY / v2TileSize or (-hT - localCellInfo.mY / 512),
                max = (localCellInfo.oY and -localCellInfo.oY / v2TileSize or (-hT - localCellInfo.mY / 512)) + hT - 1
            },
        }

        meta.localCellInfo = localCellInfo
        meta.mapTexture = mapTextures
        meta.mapInfo = mapInfo
        meta.northDirectionAngle = localCellInfo.nA or 0
        meta.eScale = tScale
        meta.zoom = meta.zoom / tScale

        local padding = mapInfo.pixelsPerCell
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
        local texture
        if not mapTextureHandler.mapInfo or (mapTextureHandler.mapInfo.version < 2 or mapTextureHandler.mapInfo.version > 3) then
            texture = mapTextureHandler.getWorldMapTexture()
        end
        local eventParams = {mapWidget = meta, mapInfo = mapTextureHandler.mapInfo, texture = texture}
        eventSys.triggerEvent(eventSys.EVENT.onWorldMapTextureInitialize, eventParams)
        mapLayout = getWorldMapTextureLayout(meta, eventParams.mapInfo, eventParams.texture)
        meta.zoom = meta.zoom / meta.eScale
    end


    meta.borderPadding = meta.borderPadding or util.vector2(0, 0)
    meta.displayMapSize = meta.displayMapSize or util.vector2(meta.mapInfo.width, meta.mapInfo.height)

    ---@type table<string, table<string, {id : string, params : advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params}>> by cell id, by marker id
    meta.zoomInMarkers = {}
    ---@type table<string, table<string, {id : string, params : advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params}>> by cell id, by marker id
    meta.zoomOutMarkers = {}
    ---@type table<string, string>
    meta.zoomMarkersCellIdById = {}
    ---@type table<integer, {[1] : string, [2] : integer, [3] : advancedWorldMap.ui.mapElementMeta}> {marker Id, layer}
    meta.activeZoomMarkers = {}
    ---@type table<integer, table<string, table>> layer id, marker id, marker layout
    meta.hiddenElements = {}
    for _, layerId in pairs(this.layerId) do
        meta.hiddenElements[layerId] = {}
    end

    local screenSize = uiUtils.getScaledScreenSize()
    local uiScale = uiUtils.getUIScale()
    meta.maxZoom = screenSize.x / (meta.mapInfo.pixelsPerCell * meta.eScale) * 5
    local minZoomDivVal = meta.cellId and 6 or 3
    meta.minZoom = math.min(screenSize.x / meta.mapInfo.width / minZoomDivVal, meta.mapInfo.pixelsPerCell / (minZoomDivVal * meta.eScale * uiScale))

    if not params.cellId and config.data.data.altExMapInfo then
        ---@diagnostic disable-next-line: undefined-field
        meta._altTexturePxDiffMul = meta.mapInfo.pixelsPerCell / config.data.data.altExMapInfo.pixelsPerCell
        meta._zoomRoundingMul = 1 / (meta._altTexturePxDiffMul % 1)
        if meta._zoomRoundingMul < 1 then
            meta._zoomRoundingMul = 1 / meta._zoomRoundingMul
        end
        if meta._zoomRoundingMul % 1 ~= 0 then
            meta._zoomRoundingMul = 1
        end

        roundMinZoom(meta)
    else
        meta._zoomRoundingMul = 1
        meta._altTexturePxDiffMul = 1
    end

    meta._lastOnZoomZoom = -1

    ---@type advancedWorldMap.ui.mapWidget.region
    meta._markerRectLimited = {bottom = 0, top = 0, left = 0, right = 0}

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
        -- for transport markers
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
                        size = util.vector2(1, 1) * config.data.legend.playerMarkerSize,
                        anchor = util.vector2(0.5, 0.5),
                        color = config.data.ui.defaultColor,
                        visible = true,
                        alpha = 0.9,
                    },
                    userData = {
                        size = util.vector2(1, 1) * config.data.legend.playerMarkerSize,
                        lastPos = playerPos.gexExteriorPos(),
                        lastYaw = playerRef.rotation:getYaw(),
                        lastLayPos = util.vector2(0, 0),
                        lastNorthAngle = meta.northDirectionAngle or 0,
                    },
                },
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

    meta.layers = mapLayers


    meta.markerEvents = {
        focusLoss = async:callback(function(e, layout)
            meta.layout.userData.inFocus = false
            local userData = layout.userData
            userData.pressed = {}
            if userData.events.focusLoss then userData.events.focusLoss(e, layout) end
            meta.layout.events.focusLoss(e, layout, userData.markerElement)
            tooltip.destroy(layout)
        end),

        mouseMove = async:callback(function(e, layout)
            meta.layout.userData.inFocus = true
            if layout.userData.pressed[1] and meta.layout.userData.lastDraggedMousePos then
                layout.userData.movedDistance = layout.userData.movedDistance +
                    (e.position - meta.layout.userData.lastDraggedMousePos):length()
            end

            if layout.userData.events.mouseMove then layout.userData.events.mouseMove(e, layout) end
            meta.layout.events.mouseMove({offset = e.offset, position = e.position}, layout, layout.userData.markerElement)

            if not layout.userData.params.tooltipContent then return end
            tooltip.createOrMove(e, layout, layout.userData.params.tooltipContent)
        end),

        mousePress = async:callback(function(e, layout)
            layout.userData.pressed[e.button] = true
            if e.button == 1 then
                layout.userData.movedDistance = 0
            end

            if layout.userData.events.mousePress then layout.userData.events.mousePress(e, layout) end
            meta.layout.events.mousePress(e, layout, layout.userData.markerElement)
        end),

        mouseRelease = async:callback(function(e, layout)
            if layout.userData.events.mouseRelease then
                layout.userData.events.mouseRelease(e, layout, layout.userData.pressed[e.button] and layout.userData.movedDistance < 30 and true or false)
            end
            layout.userData.pressed[e.button] = false
            meta.layout.events.mouseRelease(e, layout, layout.userData.markerElement)
        end),
    }


    local function setWheelZoom()
        local zoomMul = config.data.main.zoomingMul * (this.mouseWheelCount >= 0 and 1 or -1)
        local zoom = meta.zoom
        for i = 1, math.abs(this.mouseWheelCount) do
            zoom = zoomMul > 0 and zoom * zoomMul or zoom / -zoomMul
        end
        this.mouseWheelCount = 0
        if zoomMul == 0 then return end
        setZoom(meta, zoom, nil, true)
        meta:update()
    end

    meta.mouseWheelEvent = function (value, layout)
        if not layout.userData.inFocus then return end
        local tm = core.getRealTime()
        local tmDiff = tm - this.lastMouseWheelTimestamp
        this.lastMouseWheelTimestamp = tm
        if tmDiff < 0.1 then
            if this.mouseWheelTimer then
                this.mouseWheelTimer()
            end
            this.mouseWheelCount = this.mouseWheelCount + value
            this.mouseWheelTimer = realTimer.newTimer(0.12, function ()
                setWheelZoom()
                this.mouseWheelTimer = nil
            end)
            return
        else
            this.mouseWheelCount = value
        end
        setWheelZoom()
    end


    local main
    main = {
        type = ui.TYPE.Widget,
        props = {
            size = params.size,
            position = util.vector2(0, 0),
            relativePosition = params.relativePosition,
            anchor = params.anchor,
        },
        userData = {
            meta = meta,
            onMouseWheel = meta.mouseWheelEvent,

            inFocus = false,
            mousePos = util.vector2(0, 0),
            mainMouseOffset = util.vector2(0, 0),
            lastMarkerElement = nil
        },
        events = {
            mousePress = async:callback(function(e, layout, markerElement)
                meta:closeRightMouseMenu()

                main.userData.lastMarkerElement = markerElement
                e.marker = markerElement
                e.mapWidget = meta
                if markerElement then
                    e.offset = e.position - meta.screenPosition
                    main.userData.mainMouseOffset = e.offset
                end

                if eventSys.triggerEvent(eventSys.EVENT["onMousePress"], e) then
                    main.userData.lastDraggedMousePos = nil
                    return
                end

                if e.button == 1 then
                    main.userData.lastDraggedMousePos = e.position
                end
            end),

            mouseRelease = async:callback(function(e, layout, markerElement)
                main.userData.lastMarkerElement = markerElement
                e.marker = markerElement
                e.mapWidget = meta
                if markerElement then
                    e.offset = e.position - meta.screenPosition
                    main.userData.mainMouseOffset = e.offset
                end
                if eventSys.triggerEvent(eventSys.EVENT["onMouseRelease"], e) then
                    main.userData.lastDraggedMousePos = nil
                    return
                end

                if e.button == 1 then
                    main.userData.lastDraggedMousePos = nil
                end
            end),

            focusLoss = async:callback(function(_, layout, markerElement)
                main.userData.lastMarkerElement = markerElement
                main.userData.lastDraggedMousePos = nil
                main.userData.inFocus = false
                if eventSys.triggerEvent(eventSys.EVENT["onFocusLoss"], {mapWidget = meta, marker = markerElement}) then
                    main.userData.lastDraggedMousePos = nil
                    return
                end
            end),

            mouseMove = async:callback(function(e, layout, markerElement)
                main.userData.lastMarkerElement = markerElement
                main.userData.mousePos = e.position
                if not markerElement then
                    main.userData.mainMouseOffset = e.offset
                else
                    e.offset = e.position - meta.screenPosition
                    main.userData.mainMouseOffset = e.offset
                end
                main.userData.inFocus = true

                e.mapWidget = meta
                if eventSys.triggerEvent(eventSys.EVENT["onMouseMove"], {
                        position = e.position, offset = main.userData.mainMouseOffset,
                        marker = markerElement}) then
                    main.userData.lastDraggedMousePos = nil
                    return
                end

                if not main.userData.lastDraggedMousePos then return end

                local props = meta:getMapLayersLayout().props
                local mainSize = main.props.size
                local mapSize = props.size

                local newX = props.position.x - (main.userData.lastDraggedMousePos.x - e.position.x)
                local newY = props.position.y - (main.userData.lastDraggedMousePos.y - e.position.y)
                local newPos = util.vector2(newX, newY)

                newPos = clampAndCenterPosition(newPos, mapSize, mainSize)
                props.position = newPos

                meta:refreshVisibleArea()

                meta:update()

                main.userData.lastDraggedMousePos = e.position
            end),
        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                props = {
                    resource = commonData.whiteTexture,
                    relativeSize = util.vector2(1, 1),
                    color = getMapBackgroundColor(meta),
                }
            },
            {
                type = ui.TYPE.Widget,
                props = {
                    position = util.vector2(0, 0),
                    size = meta.displayMapSize,
                },
                userData = {},
                content = ui.content {
                    table.unpack(meta.layers)
                }
            }
        }
    }

    meta.layout = main

    meta:setZoom(meta.zoom, params.position and meta:getRelativePositionByWorldPosition(params.position) or nil)

    meta.initialized = true

    return main, meta
end


return this