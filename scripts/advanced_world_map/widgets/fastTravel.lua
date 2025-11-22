local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")
local types = require("openmw.types")
local playerRef = require("openmw.self")

local commonData = require("scripts.advanced_world_map.common")
local config = require("scripts.advanced_world_map.config.configLib")
local discoveredLocs = require("scripts.advanced_world_map.discoveredLocations")

local uiUtils = require("scripts.advanced_world_map.ui.utils")
local eventSys = require("scripts.advanced_world_map.eventSys")

local borders = require("scripts.advanced_world_map.ui.borders")
local checkBox = require("scripts.advanced_world_map.ui.checkBox")
local button = require("scripts.advanced_world_map.ui.button")

local l10n = core.l10n(commonData.l10nKey)

local fastTravelFunc
local rightBtnMenuFunc


local function fastTravel(menu, cellId, relPos)
    if not types.Player.isTeleportingEnabled(playerRef) then
        playerRef:sendEvent("AdvWMap:showMessage", core.getGMST("sTeleportDisabled") or "")
        return
    elseif cellId and not config.data.fastTravel.allowToInterior then
        playerRef:sendEvent("AdvWMap:showMessage", l10n("fastTravelNotAllowedToInterior"))
        return
    end

    core.sendGlobalEvent("AdvWMap:fastTravel", {
        pos = menu.mapWidget:getWorldPositionByRelativePosition(relPos),
        cellId = cellId,
        availableCells = config.data.fastTravel.onlyDiscovered and discoveredLocs.visited or nil
    })
end


---@param menu advancedWorldMap.ui.menu.map
local function create(menu)

    -- local iconLayout = {
    --     type = ui.TYPE.Text,
    --         props = {
    --         text = "Ft",
    --         textSize = config.data.ui.fontSize,
    --         textColor = config.data.ui.defaultColor,
    --         anchor = util.vector2(0.5, 0.5),
    --         size = util.vector2(menu.headerHeight - 2, menu.headerHeight - 2),
    --     },
    -- }

    local lastClick = core.getRealTime()
    local clickCount = 0
    local lastPos = menu.mapWidget:getRelativePositionOfCursor()

    if fastTravelFunc then
        eventSys.unregisterHandler(eventSys.EVENT.onMouseRelease, fastTravelFunc)
    end

    fastTravelFunc = function (e)
        if e.button ~= 1 then return end

        local time = core.getRealTime()
        local relPos = menu.mapWidget:getRelativePositionOfCursor()

        if time - lastClick >= 0.6 then
            clickCount = 0
        elseif (lastPos - relPos):length() > 0.003 then
            clickCount = -1
        elseif time - lastClick < 0.6 then
            if clickCount == 2 then
                fastTravel(menu, menu.mapWidget.cellId, relPos)

                time = 0
                clickCount = -1
            end
        end

        lastClick = time
        lastPos = relPos
        clickCount = clickCount + 1
    end
    eventSys.registerHandler(eventSys.EVENT.onMouseRelease, fastTravelFunc)


    if rightBtnMenuFunc then
        eventSys.unregisterHandler(eventSys.EVENT.onRightMouseMenu, rightBtnMenuFunc)
    end
    rightBtnMenuFunc = function (e)
        local content = e.content

        content:add(
            button{
                updateFunc = menu.update,
                text = l10n("FastTravel"),
                event = function (layout)
                    fastTravel(menu, menu.mapWidget.cellId, e.relPos)
                    menu.mapWidget:closeRightMouseMenu()
                end
            }
        )
    end
    eventSys.registerHandler(eventSys.EVENT.onRightMouseMenu, rightBtnMenuFunc)

    -- local function onOpen(content)

    -- end

    -- local function onClose()

    -- end

    -- menu:addWidget{
    --     id = "AdvancedWorldMap:FastTravel",
    --     layout = iconLayout,
    --     onOpen = onOpen,
    --     onClose = onClose,
    -- }

end


eventSys.registerHandler(eventSys.EVENT.onMenuOpened, function (e)
    if not config.data.fastTravel.enabled then return end
    create(e.menu)
end, 1000)