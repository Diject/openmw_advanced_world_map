local async = require("openmw.async")
local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")

local customTemplates = require("scripts.advanced_world_map.ui.templates")

local commonData = require("scripts.advanced_world_map.common")
local config = require("scripts.advanced_world_map.config.configLib")

local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local mathlib = require("scripts.advanced_world_map.utils.math")
local uiUtils = require("scripts.advanced_world_map.ui.utils")
local log = require("scripts.advanced_world_map.utils.log")

local dataHandler = require("scripts.advanced_world_map.mapDataHandler")
local dynamicDataHandler = require("scripts.advanced_world_map.dynamicDataHandler")

local discoveredLocs = require("scripts.advanced_world_map.discoveredLocations")

local l10n = core.l10n(commonData.l10nKey)

local button = require("scripts.advanced_world_map.ui.button")
local scrollBox = require("scripts.advanced_world_map.ui.scrollBox")
local interval = require("scripts.advanced_world_map.ui.interval")
local checkBox = require("scripts.advanced_world_map.ui.checkBox")
local mapWidget = require("scripts.advanced_world_map.ui.mapWidget")


local mapMarkerTexture = ui.texture{ path = commonData.mapMarkerPath }


local this = {}

local markersInitialized = false

local cachedMapWidgetLayout = nil
local cachedMapWidgetMetatable = nil


---@class advancedWorldMap.ui.menu.map
local menuMeta = {}
menuMeta.__index = menuMeta

menuMeta.menu = nil

function menuMeta:createMarkers()
    local widget = self.mapWidget
    local entrances = dynamicDataHandler.entrances or {}

    local entranceByLine = {}
    local lineHeight = 256
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

    for _, line in pairs(entranceByLine) do
        for i, dt in ipairs(line) do
            local textAnchor = line[i + 1] and ((line[i + 1].pos.x - dt.pos.x) < lineDiff) and 1 or 0
            local imId = string.format("%d_%d_", dt.pos.x, dt.pos.y)
            local textId = imId..tostring(textAnchor)

            widget:createTextMarker({
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
            }, true)

            widget:createImageMarker({
                id = imId,
                texture = mapMarkerTexture,
                useCache = true,
                layerId = mapWidget.layerId.marker,
                alpha = 0.5,
                anchor = util.vector2(0.5, 0.5),
                size = util.vector2(7, 7),
                pos = dt.pos,
                showWhenZoomedIn = true,
            }, true)

        end
    end
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

    local headerHeight = params.fontSize * 1.5
    local headerSize = util.vector2(meta.size.x, headerHeight)

    local mainSize = util.vector2(meta.size.x, meta.size.y - headerHeight)

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

    if not cachedMapWidgetLayout then
        cachedMapWidgetLayout, cachedMapWidgetMetatable = mapWidget.new{
            updateFunc = meta.update,
            size = mainSize,
            position = util.vector2(0, 0)
        }
    end
    local mapWidgetLayout, mapMeta = cachedMapWidgetLayout, cachedMapWidgetMetatable

    ---@type advancedWorldMap.ui.mapWidgetMeta
    meta.mapWidget = mapMeta ---@diagnostic disable-line: assign-type-mismatch
    meta.mapWidget:setUpdateFunction(meta.update)

    if not markersInitialized then
        meta:createMarkers()
        markersInitialized = true
    end

    meta.mapWidget:setZoom(meta.mapWidget.zoom)

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
            mapWidgetLayout,
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = "textures/menu_thin_border_left.dds" },
                    tileH = false,
                    tileV = true,
                    size = util.vector2(2, 0),
                    relativeSize = util.vector2(0, 1),
                    anchor = util.vector2(0, 0),
                    relativePosition = util.vector2(0, 0),
                },
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = "textures/menu_thin_border_right.dds" },
                    tileH = false,
                    tileV = true,
                    size = util.vector2(2, 0),
                    relativeSize = util.vector2(0, 1),
                    anchor = util.vector2(1, 0),
                    relativePosition = util.vector2(1, 0),
                },
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = "textures/menu_thin_border_top.dds" },
                    tileH = true,
                    tileV = false,
                    size = util.vector2(0, 2),
                    relativeSize = util.vector2(1, 0),
                    anchor = util.vector2(0, 0),
                    relativePosition = util.vector2(0, 0),
                },
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = "textures/menu_thin_border_bottom.dds" },
                    tileH = true,
                    tileV = false,
                    size = util.vector2(0, 2),
                    relativeSize = util.vector2(1, 0),
                    anchor = util.vector2(0, 1),
                    relativePosition = util.vector2(0, 1),
                },
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = "textures/menu_thin_border_top_left_corner.dds" },
                    size = util.vector2(2, 2),
                    anchor = util.vector2(0, 0),
                    relativePosition = util.vector2(0, 0),
                },
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = "textures/menu_thin_border_top_right_corner.dds" },
                    size = util.vector2(2, 2),
                    anchor = util.vector2(1, 0),
                    relativePosition = util.vector2(1, 0),
                },
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = "textures/menu_thin_border_bottom_left_corner.dds" },
                    size = util.vector2(2, 2),
                    anchor = util.vector2(0, 1),
                    relativePosition = util.vector2(0, 1),
                },
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = ui.texture{ path = "textures/menu_thin_border_bottom_right_corner.dds" },
                    size = util.vector2(2, 2),
                    anchor = util.vector2(1, 1),
                    relativePosition = util.vector2(1, 1),
                },
            },
            {
                type = ui.TYPE.Image,
                props = {
                    resource = uiUtils.whiteTexture,
                    alpha = 0.3,
                    size = util.vector2(14, 14),
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

                        local posDif = util.vector2(e.position.x - lastPos.x, e.position.y - lastPos.y)

                        local mapSize = meta.mapWidget:getSize()
                        local newSize = util.vector2(mapSize.x + posDif.x, mapSize.y + posDif.y)
                        meta.mapWidget:setSize(newSize)
                        mainLayout.props.size = newSize

                        local hSize = headerLayout.props.size
                        headerLayout.props.size = util.vector2(hSize.x + posDif.x, hSize.y)

                        local mSize = meta.size
                        mSize = util.vector2(mSize.x + posDif.x, mSize.y + posDif.y)
                        meta.menu.layout.props.size = mSize
                        meta.size = mSize

                        config.setValue("main.relativeSize.x", mSize.x / screenSize.x * 100)
                        config.setValue("main.relativeSize.y", mSize.y / screenSize.y * 100)

                        meta:update()

                        layout.userData.lastMousePos = e.position
                    end),
                },
            },
        },
    }


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
            if meta.mapWidget:updatePlayerMarker() then
                meta:update()
            end
            async:newUnsavableSimulationTimer(0.15, func)
        end
    end
    async:newUnsavableSimulationTimer(0.15, func)


    return meta
end


return this