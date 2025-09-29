local core = require('openmw.core')
local self = require('openmw.self')
local async = require('openmw.async')
local time = require('openmw_aux.time')
local ui = require('openmw.ui')
local input = require('openmw.input')
local I = require('openmw.interfaces')
local util = require('openmw.util')
local storage = require('openmw.storage')
local types = require("openmw.types")

local log = require("scripts.advanced_world_map.utils.log")

local commonData = require("scripts.advanced_world_map.common")

local configLib = require("scripts.advanced_world_map.config.configLib")

local localStorage = require("scripts.advanced_world_map.storage.localStorage")
local playerPos = require("scripts.advanced_world_map.playerPosition")

local realTimer = require("scripts.advanced_world_map.realTimer")

local mapDataHandler = require("scripts.advanced_world_map.mapDataHandler")
local menuHandler = require("scripts.advanced_world_map.menuHandler")
local dynamicDataHandler = require("scripts.advanced_world_map.dynamicDataHandler")
local discoveredLocs = require("scripts.advanced_world_map.discoveredLocations")

local mapMenu = require("scripts.advanced_world_map.ui.menu.map")

local l10n = core.l10n(commonData.l10nKey)



local function onInit()
    if not localStorage.isPlayerStorageReady() then
        localStorage.initPlayerStorage()
    end
    playerPos.init()
    mapDataHandler.init()
    discoveredLocs.init()
end


local function onLoad(data)
    localStorage.initPlayerStorage(data)
    playerPos.init()
    mapDataHandler.init()
    discoveredLocs.init()
end


local function onSave()
    local data = {}
    localStorage.save(data)
    return data
end


local function onMouseWheel(vertical)
    menuHandler.onMouseWheelCallback(vertical)
end


local function onMouseButtonRelease(buttonId)
    menuHandler.onMouseReleaseCallback(buttonId)
end


local function toggleMenu()
    if menuHandler.getMenu(commonData.mapMenuId) then
        local isModeActive = false
        for _, mode in pairs(I.UI.modes) do
            if mode == "Journal" then
                isModeActive = true
                break
            end
        end
        if isModeActive then
            I.UI.removeMode("Journal")
        else
            menuHandler.destroyMenu(commonData.mapMenuId)
        end
    else
        I.UI.addMode("Journal", {windows = {}})
        menuHandler.registerMenu(commonData.mapMenuId, mapMenu.create{})
    end
end


input.registerTriggerHandler(commonData.menuKeyId, async:callback(function()
    if types.Player.isCharGenFinished(self) then
        toggleMenu()
    end
end))


local function onKeyRelease(key)
    if key.code == input.KEY.Escape then
        menuHandler.destroyAllMenus()
    end
end


local function checkPos()
    playerPos.checkPos()
    realTimer.newTimer(0.1, function ()
        checkPos()
    end)
end

checkPos()



return {
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
        onInit = onInit,
        onKeyRelease = onKeyRelease,
        onFrame = function(dt)
            realTimer.updateTimers()
        end,
        onMouseWheel = onMouseWheel,
        onMouseButtonRelease = onMouseButtonRelease,
    },
    eventHandlers = {
        -- when changing location, a loading menu is displayed, which triggers this event
        UiModeChanged = function()
            discoveredLocs.addCell(self.cell)
            mapMenu.updateDiscoveredForCell(self.cell)
            if mapMenu.cachedMapWidgetMetatable then
                mapMenu.cachedMapWidgetMetatable:updateOnZoomMarkers()
            end
        end,
        ["AdvWMap:updateMapData"] = function (data)
            dynamicDataHandler.load(data)
        end,
    },
}