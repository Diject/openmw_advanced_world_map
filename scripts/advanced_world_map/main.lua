local async = require('openmw.async')
local world = require('openmw.world')
local types = require("openmw.types")
local core = require("openmw.core")

local config = require("scripts.advanced_world_map.config.config")

local tableLib = require("scripts.advanced_world_map.utils.table")
local stringLib = require("scripts.advanced_world_map.utils.string")
local cellLib = require("scripts.advanced_world_map.utils.cell")

local log = require("scripts.advanced_world_map.utils.log")

local common = require("scripts.advanced_world_map.common")

local dynamicDataHandler = require("scripts.advanced_world_map.dynamicDataHandler")

local l10n = core.l10n(common.l10nKey)


dynamicDataHandler.init()


return {
    engineHandlers = {

    },
    eventHandlers = {
        ["AdvWMap:updateConfigData"] = function (data)
            tableLib.applyChanges(config.data, data)
        end,

        ["AdvWMap:fastTravel"] = function (data)
            local pos = data.pos

            local gridX, gridY = cellLib.getGridCoordinates(pos)

            local doors = {}

            for x = gridX - 1, gridX + 1 do
                for y = gridY - 1, gridY + 1 do
                    local cell = world.getExteriorCell(x, y)
                    if not cell then goto continue end

                    if data.availableCells and not data.availableCells[cell.id] then goto continue end

                    for _, ref in pairs(cell:getAll(types.Door)) do
                        if types.Door.isTeleport(ref) then
                            table.insert(doors, {
                                dist = common.distance2D(pos, ref.position),
                                ref = ref,
                                pos = ref.position,
                                rot = ref.rotation,
                                cell = ref.cell,
                                dest = types.Door.destCell(ref)
                            })
                        end
                    end

                    ::continue::
                end
            end

            if not next(doors) then
                world.players[1]:sendEvent("AdvWMap:showMessage", l10n("NoLocationsForFastTravel"))
                return
            end

            table.sort(doors, function (a, b)
                return a.dist < b.dist
            end)

            local ftDoorData = doors[1]
            local ftDoorDestCell = types.Door.destCell(ftDoorData.ref)
            local ftDoorDestPos = types.Door.destPosition(ftDoorData.ref)

            local interiorDoors = {}
            for _, ref in pairs(ftDoorDestCell:getAll(types.Door)) do
                if types.Door.isTeleport(ref) then
                    table.insert(interiorDoors, {ref = ref, dist = (ftDoorDestPos - ref.position):length()})
                end
            end

            if not next(interiorDoors) then
                world.players[1]:sendEvent("AdvWMap:showMessage", l10n("NoLocationsForFastTravel"))
                return
            end

            table.sort(interiorDoors, function (a, b)
                return a.dist < b.dist
            end)


            local targetDoor = interiorDoors[1].ref

            world.players[1]:sendEvent("AdvWMap:fastTravelMessage", {
                message = l10n("fastTravelMessageBoxMessage"):format(stringLib.getBeforeComma(targetDoor.cell.name or "")),
                targetDoor = targetDoor,
            })
        end,

        ["AdvWMap:fastTravelTeleport"] = function (data)
            if not data.targetDoor then return end

            local playerRef = world.players[1]

            playerRef:teleport(types.Door.destCell(data.targetDoor), types.Door.destPosition(data.targetDoor),
                {rotation = types.Door.destRotation(data.targetDoor), onGround = true})
            playerRef:sendEvent("AdvWMap:playSound", {soundId = "mysticism hit"})
        end,
    },
}