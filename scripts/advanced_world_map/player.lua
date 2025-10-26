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
local debug = require('openmw.debug')
local ambient = require('openmw.ambient')

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
local disabledDoors = require("scripts.advanced_world_map.disabledDoors")

local mapMenu = require("scripts.advanced_world_map.ui.menu.map")

local messageBox = require("scripts.advanced_world_map.ui.menu.messageBox")

local markers = require("scripts.advanced_world_map.widgets.markers")

-- widgets
require("scripts.advanced_world_map.widgets.mapTypeLabel")
require("scripts.advanced_world_map.widgets.markers")
require("scripts.advanced_world_map.widgets.legend")
require("scripts.advanced_world_map.widgets.search")
require("scripts.advanced_world_map.widgets.fastTravel")
require("scripts.advanced_world_map.widgets.cellName")

local l10n = core.l10n(commonData.l10nKey)

local fightingActors = {}


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
    disabledDoors.init()
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


local function onCombatTargetsChanged(eventData)
    pcall(function ()
        if eventData.actor == nil then return end

        if next(eventData.targets) ~= nil then
            fightingActors[eventData.actor.id] = true
        else
            fightingActors[eventData.actor.id] = nil
        end
    end)
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


local lastPlayerCellId

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
        UiModeChanged = function(e)
            if e.oldMode == "Loading" or e.oldMode == nil and e.newMode == nil and lastPlayerCellId ~= self.cell.id then
                lastPlayerCellId = self.cell.id

                discoveredLocs.addCell(self.cell)
                markers.updateDiscoveredForCell(self.cell)

                local cellId = self.cell.isExterior and commonData.exteriorMapId or self.cell.id
                if mapMenu.cachedMapWidgetMetatable[cellId] then
                    mapMenu.cachedMapWidgetMetatable[cellId]:updateOnZoomMarkers()
                end

                local menu = menuHandler.getMenu(commonData.mapMenuId)
                if menu and menu:updateMapWidgetCell(cellId) then
                    menu:update()
                end

                core.sendGlobalEvent("AdvWMap:cellChanged")
            end
        end,

        OMWMusicCombatTargetsChanged = onCombatTargetsChanged,

        ["AdvWMap:updateMapData"] = function (data)
            dynamicDataHandler.load(data)
        end,

        ["AdvWMap:showMessage"] = function (str)
            ui.showMessage(str)
        end,

        ["AdvWMap:playSound"] = function (data)
            ambient.playSound(data.soundId, {})
        end,

        ["AdvWMap:fastTravelMessage"] = function (data)
            if next(fightingActors) ~= nil and debug.isAIEnabled() then
                ui.showMessage(l10n("fastTravelWhileInCombat"))
                return
            end

            local cost = configLib.data.fastTravel.baseMagickaCost
            if not self.cell.isExterior then
                cost = cost * 1.5
            end

            cost = cost + (playerPos.gexExteriorPos() - types.Door.destPosition(data.targetDoor)):length() / 8192 * configLib.data.fastTravel.additionalCost
            cost = math.floor(math.max(0, cost * (1.75 - types.NPC.stats.skills.mysticism(self).modified / 100)))

            menuHandler.registerMenu(commonData.messageBoxMenuId, messageBox.newSimple{
                message = data.message.."\n"..l10n("fastTraveMagickaCost"):format(cost),
                relativeSize = util.vector2(0.25, 0.2),
                yesCallback = function ()
                    local currentMagicka = types.Actor.stats.dynamic.magicka(self).current
                    if currentMagicka < cost then
                        ui.showMessage(l10n("NotEnoughMagicka"))
                        return
                    end

                    types.Actor.stats.dynamic.magicka(self).current = currentMagicka - cost

                    discoveredLocs.blockDiscovery = true
                    core.sendGlobalEvent("AdvWMap:fastTravelTeleport", data)
                    async:newUnsavableSimulationTimer(0.5, function ()
                        discoveredLocs.blockDiscovery = false
                    end)

                    if I.SkillProgression then
                        I.SkillProgression.skillUsed("mysticism", {
                            useType = I.SkillProgression.SKILL_USE_TYPES.Spellcast_Success,
                        })
                    end
                end,
            })
        end,

        ["AdvWMap:registerDisabledDoor"] = function(ref)
            disabledDoors.register(ref.id)
            markers.updateDoorMarkerVisibility(ref)
        end,

        ["AdvWMap:unregisterDisabledDoor"] = function(ref)
            disabledDoors.unregister(ref.id)
            markers.updateDoorMarkerVisibility(ref)
        end,
    },
}