local core = require('openmw.core')
local self = require('openmw.self')
local async = require('openmw.async')
local time = require('openmw_aux.time')
local ui = require('openmw.ui')
local input = require('openmw.input')
local I = require('openmw.interfaces')
local util = require('openmw.util')
local storage = require('openmw.storage')

local log = require("scripts.advanced_world_map.utils.log")

local commonData = require("scripts.advanced_world_map.common")

local configLib = require("scripts.advanced_world_map.config.configLib")

local localStorage = require("scripts.advanced_world_map.storage.localStorage")

local realTimer = require("scripts.advanced_world_map.realTimer")

local menuHandler = require("scripts.advanced_world_map.menuHandler")

local l10n = core.l10n(commonData.l10nKey)


---@type table<string, any>
local activeMenus = {}


local function onInit()
    if not localStorage.isPlayerStorageReady() then
        localStorage.initPlayerStorage()
    end
end


local function onLoad(data)
    localStorage.initPlayerStorage(data)
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


input.registerTriggerHandler(commonData.menuKeyId, async:callback(function()

end))


local function onKeyRelease(key)
    if key.code == input.KEY.Escape then
        menuHandler.destroyAllMenus()
    end
end



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

    },
}