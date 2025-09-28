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

local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local uiUtils = require("scripts.advanced_world_map.ui.utils")
local cellLib = require("scripts.advanced_world_map.utils.cell")
local log = require("scripts.advanced_world_map.utils.log")

local tooltip = require("scripts.advanced_world_map.ui.tooltip")

local l10n = core.l10n(commonData.l10nKey)


local mapMarkerTexture = ui.texture{ path = commonData.mapMarkerPath }
local playerMarkerTexture = ui.texture{ path = commonData.playerMapMarkerPath }

local mapTexture

local zoomInOffsetInWorldCoord = 24576
local zoomOutOffsetInWorldCoord = 24576



local this = {}

local uniquesId = 0
this.getUniqueId = function ()
    uniquesId = uniquesId + 1
    return uniquesId
end


this.layerId = {
    map = 1,
    region = 2,
    name = 3,
    player = 4,
    nonInteractive = 5,
    marker = 6,
}


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


---@class advancedWorldMap.ui.mapWidgetMeta
local mapWidgetMeta = {}
mapWidgetMeta.__index = mapWidgetMeta

mapWidgetMeta.getUniqueId = function (self)
    return this.getUniqueId()
end


function mapWidgetMeta:getMapImageWidget()
    return self.layout.content[2]
end

function mapWidgetMeta:getLayerLayout(id)
    return self:getMapImageWidget().content[id]
end

function mapWidgetMeta:getMapLayout()
    return self:getMapImageWidget().content[1]
end

function mapWidgetMeta:getRegionLayout()
    return self:getMapImageWidget().content[2]
end

function mapWidgetMeta:getNameLayout()
    return self:getMapImageWidget().content[3]
end

function mapWidgetMeta:getMarkerLayout()
    return self:getMapImageWidget().content[6]
end

function mapWidgetMeta:getPlayerLayout()
    return self:getMapImageWidget().content[4]
end


function mapWidgetMeta:getRelativeCenter()
    return util.vector2(
        (0 - self.mapInfo.gridX.min) / (self.mapInfo.gridX.max - self.mapInfo.gridX.min + 1),
        (0 - self.mapInfo.gridY.min) / (self.mapInfo.gridY.max - self.mapInfo.gridY.min + 1)
    )
end

function mapWidgetMeta:getRelativePositionByWorldPosition(worldPos)
    local center = self:getRelativeCenter()
    local x = worldPos.x / 8192
    local y = worldPos.y / 8192

    return util.vector2(
        center.x + x * self.mapInfo.pixelsPerCell / self.mapInfo.width,
        1 - center.y - y * self.mapInfo.pixelsPerCell / self.mapInfo.height
    )
end


function mapWidgetMeta:getAbsolutePositionByWorldPosition(worldPos)
    local cellX = worldPos.x / 8192
    local cellY = worldPos.y / 8192
    local x = (cellX - self.mapInfo.gridX.min) * self.mapInfo.pixelsPerCell
    local y = (self.mapInfo.gridY.max - cellY) * self.mapInfo.pixelsPerCell
    return util.vector2(x, y) * self.zoom
end


local function clampAndCenterPosition(pos, mapSize, mainSize)
    local newX, newY

    if mapSize.x * 1.25 <= mainSize.x then
        newX = (mainSize.x - mapSize.x) / 2
    else
        newX = util.clamp(pos.x, mainSize.x - mapSize.x * 1.25, mapSize.x * 0.25)
    end

    if mapSize.y * 1.25 <= mainSize.y then
        newY = (mainSize.y - mapSize.y) / 2
    else
        newY = util.clamp(pos.y, mainSize.y - mapSize.y * 1.25, mapSize.y * 0.25)
    end

    return util.vector2(newX, newY)
end


---@return advancedWorldMap.ui.mapWidget.region rect
function mapWidgetMeta:getVisibleMapRect()
    local widget = self:getMapImageWidget()
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

    local left = (rect.left + xOffset) * pixelSize
    local top = (-rect.top + yOffset) * pixelSize
    local right = (rect.right + xOffset) * pixelSize
    local bottom = (-rect.bottom + yOffset) * pixelSize

    return { left = left, top = top, right = right, bottom = bottom }, rect
end


function mapWidgetMeta:getWorldPositionOfVisibleCenter()
    local rect = self:getVisibleMapRect()

    local zoomedPixPerCell = self.mapInfo.pixelsPerCell * self.zoom
    local pixelSize = 8192 / zoomedPixPerCell
    local xOffset = self.mapInfo.gridX.min * zoomedPixPerCell
    local yOffset = self.mapInfo.gridY.max * zoomedPixPerCell

    local centerX = (rect.left + rect.right) / 2
    local centerY = (rect.top + rect.bottom) / 2

    return util.vector2(
        (centerX + xOffset) * pixelSize,
        (-centerY + yOffset) * pixelSize
    )
end


function mapWidgetMeta:getRelativePositionOfVisibleCenter()
    local rect = self:getVisibleMapRect()
    local centerX = (rect.left + rect.right) / 2
    local centerY = (rect.top + rect.bottom) / 2
    local relX = centerX / (self.mapInfo.width * self.zoom)
    local relY = centerY / (self.mapInfo.height * self.zoom)

    return util.vector2(relX, relY)
end


function mapWidgetMeta:getSize()
    return self.layout.props.size
end

function mapWidgetMeta:setSize(newSize)
    self.maxZoom = math.min(newSize.x / self.mapInfo.pixelsPerCell, newSize.y / self.mapInfo.pixelsPerCell) * 3
    self.minZoom = math.min(newSize.x / self.mapInfo.width, newSize.y / self.mapInfo.height) / 2
    self.layout.props.size = newSize
end


function mapWidgetMeta:updateOnZoomMarkers()
    local visibleRect = self:getVisibleMapRectInWorldCoordinates()
    if self.zoom > 6 then
        visibleRect.bottom = visibleRect.bottom - zoomInOffsetInWorldCoord
        visibleRect.top = visibleRect.top + zoomInOffsetInWorldCoord
        visibleRect.left = visibleRect.left - zoomInOffsetInWorldCoord
        visibleRect.right = visibleRect.right + zoomInOffsetInWorldCoord
        self:removeOnZoomMarkers()
        self:createZoomInMarkers(visibleRect)
        self:placeGroundTextures(visibleRect)
    else
        visibleRect.bottom = visibleRect.bottom - zoomOutOffsetInWorldCoord
        visibleRect.top = visibleRect.top + zoomOutOffsetInWorldCoord
        visibleRect.left = visibleRect.left - zoomOutOffsetInWorldCoord
        visibleRect.right = visibleRect.right + zoomOutOffsetInWorldCoord
        self:removeOnZoomMarkers()
        self:createZoomOutMarkers(visibleRect)
        self:removeGroundTextures()
    end
end



local function setZoom(self, zoom, relativePos)
    local widget = self:getMapImageWidget()

    local oldZoom = self.zoom
    local oldSize = util.vector2(self.mapInfo.width * oldZoom, self.mapInfo.height * oldZoom)

    zoom = util.clamp(zoom, self.minZoom, self.maxZoom)

    local newSize = util.vector2(self.mapInfo.width * zoom, self.mapInfo.height * zoom)
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

    localStorage.data[commonData.lastZoomFieldId] = zoom
end

---@param zoom number
function mapWidgetMeta:setZoom(zoom, relativePos)
    setZoom(self, zoom, relativePos or self:getRelativePositionOfVisibleCenter())
end


function mapWidgetMeta:focusOnWorldPosition(worldPos)
    local widget = self:getMapImageWidget()
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
    playerMarkerLayout.content[1].props.resource = playerMarker.getTexture() or playerMarkerTexture

    for _, layout in pairs({self:getLayerLayout(this.layerId.nonInteractive), self:getLayerLayout(this.layerId.marker),
            self:getLayerLayout(this.layerId.name), self:getLayerLayout(this.layerId.region)}) do
        for i, elem in pairs(layout.content) do
            if elem.userData and elem.userData.autoScale then
                if elem.userData.fontSize then
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
                elseif elem.userData.size then
                    elem.props.size = (elem.userData.scaleFunc or this.scaleFunction.marker)(elem.userData.size, self.zoom)
                end
            end
        end
    end
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

---@class advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params
---@field layerId integer
---@field id string?
---@field pos any in the game world
---@field text string
---@field events table?
---@field tooltipContent any
---@field fontSize number?
---@field color any util.color.rgb
---@field anchor any util.vector2
---@field textAlignH any ui.ALIGNMENT
---@field alpha number?
---@field visible boolean?
---@field showWhenZoomedIn boolean?
---@field showWhenZoomedOut boolean?
---@field scaleFunc (fun(size: any, zoom: number): number)?
---@field useCache boolean?


---@param params advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
---@return string? id
---@return integer? layerId
local function createMarker(self, params, onlyInitialize)
    if not params then params = {layerId = this.layerId.marker} end
    if not params.layerId then return end

    local content = self:getLayerLayout(params.layerId).content

    if params.id and uiUtils.isExistsInContent(content, params.id) then
        return params.id, params.layerId
    end

    local function addZoomInOutData(id, layout)
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
            params.showWhenZoomedIn = false
            table.insert(self.activeZoomMarkers, {id, params.layerId})
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
            params.showWhenZoomedOut = false
            table.insert(self.activeZoomMarkers, {id, params.layerId})
        end
    end

    if not onlyInitialize and params.useCache and params.id then
        local id = params.id
        local cacheId = id.."_"..tostring(params.layerId)
        local cachedLayout = createMarkerFuncCache[cacheId]
        if cachedLayout then
            addZoomInOutData(id, cachedLayout)
            if cachedLayout.props.textSize then
                cachedLayout.props.textSize = (cachedLayout.userData.scaleFunc or this.scaleFunction.marker)(cachedLayout.userData.fontSize, self.zoom)
            else
                cachedLayout.props.size = (cachedLayout.userData.scaleFunc or this.scaleFunction.marker)(cachedLayout.userData.size, self.zoom)
            end
            local res = uiUtils.safeAddToContent(content, cachedLayout)
            if res then
                return id, params.layerId
            else
                return
            end
        end
    end

    params.pos = params.pos or util.vector3(0, 0, 0)
    local relPos = self:getRelativePositionByWorldPosition(params.pos)

    local fontSize = params.fontSize or 18
    local color = params.color or config.data.ui.defaultColor
    local alpha = params.alpha or 1
    local anchor = params.anchor or util.vector2(0.5, 0.5)
    local tooltipContent = params.tooltipContent

    local size = params.size or util.vector2(18, 18)
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
            textSize = params.text and (params.scaleFunc or this.scaleFunction.marker)(fontSize, self.zoom),
            anchor = anchor,
            relativePosition = relPos,
            textColor = params.text and color,
            visible = params.visible,
            alpha = alpha,
            resource = texture,
            size = this.scaleFunction.marker(size, self.zoom),
            color = params.texture and color,
            propagateEvents = false,
        },
        userData = {
            scaleFunc = params.scaleFunc,
            autoScale = true,
            fontSize = params.text and fontSize,
            size = params.texture and size,
        },
        events = {
            focusLoss = async:callback(function(e, layout)
                self.layout.userData.inFocus = false
                marker.userData.pressed = false
                if events.focusLoss then events.focusLoss(e, layout) end
                self.layout.events.focusLoss(e, layout)
                tooltip.destroy(layout)
            end),

            mouseMove = async:callback(function(e, layout)
                self.layout.userData.inFocus = true
                self.layout.userData.additiveMouseOffset = e.offset

                if events.mouseMove then events.mouseMove(e, layout) end
                self.layout.events.mouseMove({offset = e.offset, position = e.position}, layout)

                if not tooltipContent then return end
                tooltip.createOrMove(e, layout, tooltipContent)
            end),

            mousePress = async:callback(function(e, layout)
                marker.userData.pressed = true
                if events.mousePress then events.mousePress(e, layout) end
                self.layout.events.mousePress(e, layout)
            end),

            mouseRelease = async:callback(function(e, layout)
                if events.mouseRelease then events.mouseRelease(e, layout, marker.userData.pressed) end
                marker.userData.pressed = false
                self.layout.events.mouseRelease(e, layout)
            end),
        }
    }

    createMarkerFuncCache[markerName.."_"..tostring(params.layerId)] = marker

    addZoomInOutData(markerName, marker)

    if onlyInitialize or not uiUtils.safeAddToContent(content, marker) then return end

    return markerName, params.layerId
end


---@param params advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
---@return string? id
---@return integer? layerId
function mapWidgetMeta:createImageMarker(params)
    if not params.texture then return end
    return createMarker(self, params, (params.showWhenZoomedIn or params.showWhenZoomedOut) and true)
end

---@param params advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params
---@return string? id
---@return integer? layerId
function mapWidgetMeta:createTextMarker(params)
    if not params.text then return end
    return createMarker(self, params, (params.showWhenZoomedIn or params.showWhenZoomedOut) and true)
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


function mapWidgetMeta:removeOnZoomMarkers()
    for i, dt in pairs(self.activeZoomMarkers) do
        removeMarker(self, dt[1], dt[2])
        self.activeZoomMarkers[i] = nil
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

            if not texture then goto continue end

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



---@return boolean
function mapWidgetMeta:updatePlayerMarker()
    local playerMarkerLayout = self:getPlayerLayout().content[1]
    local exPos = playerPos.gexExteriorPos()
    local dist = (playerMarkerLayout.userData.lastPos - exPos):length()

    local yaw = playerRef.rotation:getYaw()
    local lastYaw = playerMarkerLayout.userData.lastYaw

    if dist < (8192 / (self.mapInfo.pixelsPerCell * self.zoom)) and (math.abs(yaw - lastYaw) < 0.1) then return false end

    local playerRelPos = self:getRelativePositionByWorldPosition(exPos)
    playerMarkerLayout.props.relativePosition = playerRelPos
    playerMarkerLayout.props.resource = playerMarker.getTexture() or playerMarkerTexture
    playerMarkerLayout.userData.lastPos = exPos
    playerMarkerLayout.userData.lastYaw = yaw

    return true
end


function mapWidgetMeta:setUpdateFunction(func)
    self.update = func
end



---@class advancedWorldMap.ui.mapWidget.params
---@field size any
---@field fontSize integer?
---@field position any?
---@field relativePosition any?
---@field anchor any?
---@field updateFunc function

---@param params advancedWorldMap.ui.mapWidget.params
---@return table?
---@return advancedWorldMap.ui.mapWidgetMeta?
function this.new(params)
    if not mapTexture then
        if not dataHandler.mapInfo or not dataHandler.mapImagePath then return end

        local mapImagePath = dataHandler.mapImagePath

        if not vfs.fileExists(mapImagePath) then return end

        mapTexture = ui.texture{ path = mapImagePath }
    end

    params.fontSize = params.fontSize or 18

    ---@class advancedWorldMap.ui.mapWidgetMeta
    local meta = setmetatable({}, mapWidgetMeta)

    meta.params = params
    meta.mapTexture = mapTexture
    meta.mapInfo = dataHandler.mapInfo

    ---@type table<string, table<string, {id : string, params : any}>> by cell id, by marker id
    meta.zoomInMarkers = {}
    ---@type table<string, table<string, {id : string, params : any}>> by cell id, by marker id
    meta.zoomOutMarkers = {}
    ---@type table<string, string>
    meta.zoomMarkersCellIdById = {}
    ---@type {[2] : string, [1] : integer}[] {marker Id, layer}
    meta.activeZoomMarkers = {}

    meta.zoom = 1
    meta.maxZoom = math.min(params.size.x / meta.mapInfo.pixelsPerCell, params.size.y / meta.mapInfo.pixelsPerCell) * 3
    meta.minZoom = math.min(params.size.x / meta.mapInfo.width, params.size.y / meta.mapInfo.height) / 2

    meta.update = function(self)
        params.updateFunc()
    end

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
            mousePress = async:callback(function(e, layout)
                main.userData.lastMousePos = e.position
            end),

            mouseRelease = async:callback(function(_, layout)
                main.userData.lastMousePos = nil
            end),

            focusLoss = async:callback(function(_, layout)
                main.userData.lastMousePos = nil
                main.userData.inFocus = false
            end),

            mouseMove = async:callback(function(e, layout)
                if e.offset then
                    main.userData.mainMouseOffset = e.offset
                    main.userData.additiveMouseOffset = util.vector2(0, 0)
                end
                main.userData.inFocus = true

                if not main.userData.lastMousePos then return end

                local props = meta:getMapImageWidget().props
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
                    color = commonData.mapWaterColor,
                }
            },
            {
                type = ui.TYPE.Widget,
                props = {
                    position = util.vector2(0, 0),
                    size = util.vector2(meta.mapInfo.width, meta.mapInfo.height),
                },
                userData = {},
                content = ui.content {
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
                                    resource = meta.mapTexture,
                                    relativeSize = util.vector2(1, 1),
                                }
                            },
                        },
                    },
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
                                    resource = playerMarker.getTexture() or playerMarkerTexture,
                                    size = util.vector2(32, 32),
                                    anchor = util.vector2(0.5, 0.5),
                                    color = config.data.ui.defaultColor,
                                    visible = true,
                                    alpha = 0.6,
                                },
                                userData = {
                                    size = util.vector2(32, 32),
                                    lastPos = playerPos.gexExteriorPos(),
                                    lastYaw = playerRef.rotation:getYaw()
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
            }
        }
    }

    meta.layout = main

    meta:focusOnWorldPosition(playerPos.gexExteriorPos())
    meta:setZoom(localStorage.data[commonData.lastZoomFieldId] or 1)

    return main, meta
end


return this