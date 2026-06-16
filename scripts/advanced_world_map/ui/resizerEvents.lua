local async = require("openmw.async")
local util = require("openmw.util")
local config = require("scripts.advanced_world_map.config.configLib")
local eventSys = require("scripts.advanced_world_map.eventSys")

local resizerEvents = {
    mousePress = async:callback(function(e, layout)
        if e.button ~= 1 then return end
        layout.userData.lastMousePos = e.position
    end),

    mouseRelease = async:callback(function(e, layout)
        if e.button ~= 1 then return end
        local userData = layout.userData
        userData.lastMousePos = nil
        local meta = userData.getMeta()
        meta.mapWidget:updateMarkers(true)
        meta:update()
    end),

    mouseMove = async:callback(function(e, layout)
        local userData = layout.userData
        local lastPos = userData.lastMousePos
        if not lastPos then return end

        ---@type advancedWorldMap.ui.menu.map
        local meta = userData.getMeta()
        local screenSize = meta.screenSize

        meta:closeActiveWidget()

        local xDif, yDif = 0, 0
        if userData.left or userData.right then
            xDif = e.position.x - lastPos.x
            if userData.left then
                xDif = -xDif
            end
        end
        if userData.top or userData.bottom then
            yDif = e.position.y - lastPos.y
            if userData.top then
                yDif = -yDif
            end
        end

        local minSize = util.vector2(50, 50)

        local mapSize = meta.mapWidget:getSize()
        local newSize = util.vector2(math.max(minSize.x, mapSize.x + xDif), math.max(minSize.y, mapSize.y + yDif))

        local size = meta:setMapWidgetSize(newSize)

        if not meta.minimapSetupMode then
            config.setValue("main.relativeSize.x", size.x / screenSize.x * 100)
            config.setValue("main.relativeSize.y", size.y / screenSize.y * 100)
        end

        meta.defaultMainSize = meta.mainLayout.props.size

        if userData.left or userData.top then
            local menuPos = meta.menu.layout.props.relativePosition:emul(screenSize)
            local newMenuPos = util.vector2(menuPos.x - xDif, menuPos.y - yDif)
            meta.menu.layout.props.relativePosition = newMenuPos:ediv(screenSize)
            meta.screenPosition = newMenuPos + util.vector2(meta:getWidgetWindowWidth(), meta.headerFullHeight) +
                util.vector2(meta.borderSize, meta.borderSize)
            meta.mapWidget.screenPosition = meta.screenPosition

            if not meta.minimapSetupMode then
                config.setValue("main.relativePosition.y", meta.menu.layout.props.relativePosition.y * 100)
                config.setValue("main.relativePosition.x", meta.menu.layout.props.relativePosition.x * 100)
            end
        end

        eventSys.triggerEvent(eventSys.EVENT["onResized"], {
            menu = meta,
            size = size,
            mapWidgetSize = newSize
        })

        meta:update()

        layout.userData.lastMousePos = e.position
    end),
}

return resizerEvents