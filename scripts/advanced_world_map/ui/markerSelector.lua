local util = require("openmw.util")
local I = require("openmw.interfaces")

local commonData = require("scripts.advanced_world_map.common")
local eventSys = require("scripts.advanced_world_map.eventSys")
local menuMode = require("scripts.advanced_world_map.ui.menuMode")
local menuHandler = require("scripts.advanced_world_map.menuHandler")
local config = require("scripts.advanced_world_map.config.config")

local tooltip = require("scripts.advanced_world_map.ui.tooltip")


local this = {}

---@type advancedWorldMap.ui.menu.map
this.activeMenuMeta = nil
---@type advancedWorldMap.ui.mapElementMeta?
this.lastSelected = nil


local function isInValidRect(p, f, cP, lV)
    if f <= 0 then return false end

    local d = lV.x * (f - cP.y) - lV.y * (p - cP.x)
    return d >= 0
end


---@class advancedWorldMap.ui.markerSelector.centerOnNextMarker.params
---@field mapWidget advancedWorldMap.ui.mapWidgetMeta
---@field direction integer 1 - top, 2 - right, 3 - bottom, 4 - left

---@param params advancedWorldMap.ui.markerSelector.centerOnNextMarker.params
function this.centerOnNextMarker(params)

    local mapWidget = params.mapWidget
    local rect = mapWidget:getVisibleMapRectInWorldCoordinates()
    local center = mapWidget:getWorldPositionOfVisibleCenter()
    local centerRel = mapWidget:getRelativePositionOfVisibleCenter()

    local coneV = util.vector2(0.75, 1)

    ---@type advancedWorldMap.ui.mapElementMeta?
    local best
    local bestForward

    for _, m in pairs(mapWidget:getActiveMarkers()) do
        if not m:getVisibility() or m:getAlpha() <= 0.01 then goto continue end

        local userData = m:getUserData()
        if not userData or not (m._layerId == mapWidget.LAYER.marker and userData.selectable ~= false and
                (m._params.tooltipContent or m._container.userData.events.mouseRelease) or userData.selectable == true or
                (userData.type == commonData.doorMarkerType and userData.textMarker and userData.textMarker:getUserData().clustered ~= true)) then
            goto continue
        end

        local pos = m:getPosition()
        if not mapWidget.isPointInRegion(rect, pos.x, pos.y) or commonData.distance2D(pos, center) < 1 then goto continue end

        local relPos = m._container.props.relativePosition
        if not relPos then goto continue end

        local dx = relPos.x - centerRel.x
        local dy = centerRel.y - relPos.y

        local forward, perpendicular
        if params.direction == 1 then -- top
            forward = dy
            perpendicular = math.abs(dx)
        elseif params.direction == 2 then -- right
            forward = dx
            perpendicular = math.abs(dy)
        elseif params.direction == 3 then -- bottom
            forward = -dy
            perpendicular = math.abs(dx)
        elseif params.direction == 4 then -- left
            forward = -dx
            perpendicular = math.abs(dy)
        else
            goto continue
        end

        if not isInValidRect(perpendicular, forward, util.vector2(perpendicular * 0.3, 0), coneV) then goto continue end

        local angle = (math.atan2 or math.atan)(perpendicular, forward)
        local effectiveForward = forward * (1 + angle / 0.52) -- 30 deg

        if not best or effectiveForward < bestForward then
            best = m
            bestForward = effectiveForward
        end

        ::continue::
    end

    if best then
        this.resetMenuState()
        mapWidget:focusOnWorldPosition(best:getPosition())
        mapWidget:updateMarkers()
        mapWidget:update()

        if best._container.events and best._container.events.mouseMove then
            local halfSize = mapWidget.layout.props.size:emul(util.vector2(0.5, 0.5))
            best._container.events.mouseMove(
                {position = mapWidget.screenPosition + halfSize, offset = halfSize, keepSelectedMarker = true},
                best._container
            )
        end

        if best._params.tooltipContent then
            local halfSize = mapWidget.layout.props.size:emul(util.vector2(0.5, 0.5))
            tooltip.createOrMove({position = mapWidget.screenPosition + halfSize}, best._container, best._params.tooltipContent)
        end

        this.lastSelected = best
    end
end


function this.resetLastSelected()
    this.lastSelected = nil
end


function this.resetMenuState()
    local lastSelected = this.lastSelected
    if not lastSelected then return end

    if lastSelected._container.events and lastSelected._container.events.focusLoss then
        local ss, msg = pcall(function ()
            local parent = lastSelected._parent
            parent.markerEvents.focusLoss(nil, lastSelected._container)
            parent:closeRightMouseMenu()
            parent:focusOn()
            -- local halfSize = parent.layout.props.size:emul(util.vector2(0.5, 0.5))
            -- parent:setMousePos(parent.screenPosition + halfSize)
            tooltip.destroy(lastSelected._container)
        end)
        if not ss then print(msg) end
    end
end


function this.clickOnSelected()
    if not menuMode.isMenuInteractive() then return end
    if not this.lastSelected or not this.lastSelected._container.userData.inFocus then return end

    local mapWidget = this.lastSelected._parent
    local userData = this.lastSelected._container.userData

    local halfSize = mapWidget.layout.props.size:emul(util.vector2(0.5, 0.5))

    local eParam = {position = mapWidget.screenPosition + halfSize, offset = halfSize, button = 1}
    if userData.events.mousePress then userData.events.mousePress(eParam, this.lastSelected._container) end
    if userData.events.mouseRelease then userData.events.mouseRelease(eParam, this.lastSelected._container, true) end
end


local directionHotkeyFuncs = {}
for i = 1, 4 do
    directionHotkeyFuncs[i] = function ()
        if not menuMode.isMenuInteractive() or not menuHandler.getMenu(commonData.mapMenuId) or
            not this.activeMenuMeta then return end

        this.centerOnNextMarker{
            mapWidget = this.activeMenuMeta.mapWidget,
            direction = i
        }
    end
end


local function registerHotkeys()
    I.DijectKeyBindings.action.register(commonData.topMarkerKeyId, directionHotkeyFuncs[1])
    if I.DijectKeyBindings.getActionKey(commonData.topMarkerKeyId) == config.default.input.topMarkerHotkey then
        I.DijectKeyBindings.keybind.register("UpArrow", directionHotkeyFuncs[1])
    end
    I.DijectKeyBindings.action.register(commonData.rightMarkerKeyId, directionHotkeyFuncs[2])
    if I.DijectKeyBindings.getActionKey(commonData.rightMarkerKeyId) == config.default.input.rightMarkerHotkey then
        I.DijectKeyBindings.keybind.register("RightArrow", directionHotkeyFuncs[2])
    end
    I.DijectKeyBindings.action.register(commonData.bottomMarkerKeyId, directionHotkeyFuncs[3])
    if I.DijectKeyBindings.getActionKey(commonData.bottomMarkerKeyId) == config.default.input.bottomMarkerHotkey then
        I.DijectKeyBindings.keybind.register("DownArrow", directionHotkeyFuncs[3])
    end
    I.DijectKeyBindings.action.register(commonData.leftMarkerKeyId, directionHotkeyFuncs[4])
    if I.DijectKeyBindings.getActionKey(commonData.leftMarkerKeyId) == config.default.input.leftMarkerHotkey then
        I.DijectKeyBindings.keybind.register("LeftArrow", directionHotkeyFuncs[4])
    end

    I.DijectKeyBindings.keybind.register("C_A", this.clickOnSelected)
end

local function unregisterHotkeys()
    I.DijectKeyBindings.action.unregister(commonData.topMarkerKeyId, directionHotkeyFuncs[1])
    I.DijectKeyBindings.action.unregister(commonData.rightMarkerKeyId, directionHotkeyFuncs[2])
    I.DijectKeyBindings.action.unregister(commonData.bottomMarkerKeyId, directionHotkeyFuncs[3])
    I.DijectKeyBindings.action.unregister(commonData.leftMarkerKeyId, directionHotkeyFuncs[4])

    I.DijectKeyBindings.keybind.unregister("UpArrow", directionHotkeyFuncs[1])
    I.DijectKeyBindings.keybind.unregister("RightArrow", directionHotkeyFuncs[2])
    I.DijectKeyBindings.keybind.unregister("DownArrow", directionHotkeyFuncs[3])
    I.DijectKeyBindings.keybind.unregister("LeftArrow", directionHotkeyFuncs[4])

    I.DijectKeyBindings.keybind.unregister("C_A", this.clickOnSelected)
end


eventSys.registerHandler(eventSys.EVENT.onMenuOpened, function (e)
    this.activeMenuMeta = e.menu
    registerHotkeys()
end, 10001)


eventSys.registerHandler(eventSys.EVENT.onMenuClosed, function (e)
    this.resetMenuState()
    this.activeMenuMeta = nil
    unregisterHotkeys()
end, 10001)


eventSys.registerHandler(eventSys.EVENT.onMapClosed, function (e)
    this.resetMenuState()
    this.resetLastSelected()
end, 10001)


return this