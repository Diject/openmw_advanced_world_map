local async = require('openmw.async')
local world = require('openmw.world')
local types = require("openmw.types")
local core = require("openmw.core")

local Door = types.Door

local config = require("scripts.advanced_world_map.config.config")

local tableLib = require("scripts.advanced_world_map.utils.table")
local stringLib = require("scripts.advanced_world_map.utils.string")
local cellLib = require("scripts.advanced_world_map.utils.cell")

local log = require("scripts.advanced_world_map.utils.log")

local common = require("scripts.advanced_world_map.common")

local saveStorage = require("scripts.advanced_world_map.storage.localStorage")
local mapDataHandler = require("scripts.advanced_world_map.mapDataHandler")

local disabledDoors = require("scripts.advanced_world_map.disabledDoors")

local l10n = core.l10n(common.l10nKey)


saveStorage.initPlayerStorage()

mapDataHandler.init()


local function checkDoor(ref)
    if Door.objectIsInstance(ref) and Door.isTeleport(ref) then
        local wasDisabled = disabledDoors.contains(ref.id)

        if not ref.enabled then
            disabledDoors.register(ref.id)
            if not wasDisabled then
                world.players[1]:sendEvent("AdvWMap:registerDisabledDoor", ref)
            end

        elseif wasDisabled then
            disabledDoors.unregister(ref.id)
            world.players[1]:sendEvent("AdvWMap:unregisterDisabledDoor", ref)
        end

    end
end


return {
    engineHandlers = {
        onLoad = function (data)
            saveStorage.initPlayerStorage(data)
            disabledDoors.init()
        end
    },
    eventHandlers = {
        ["AdvWMap:updateConfigData"] = function (data)
            tableLib.applyChanges(config.data, data)
        end,

        ["AdvWMap:fastTravel"] = function (data)
            local pos = data.pos
            local cellId = data.cellId
            local playerRef = world.players[1]

            local doors = {}

            local function processCell(cell)
                for _, ref in pairs(cell:getAll(types.Door)) do

                    if types.Door.isTeleport(ref) then
                        local dest = types.Door.destCell(ref)
                        if dest and (not data.availableCells or data.availableCells[dest.id]) then
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

                end
            end

            if not cellId then
                local gridX, gridY = cellLib.getGridCoordinates(pos)
                for x = gridX - 1, gridX + 1 do
                    for y = gridY - 1, gridY + 1 do
                        local cell = world.getExteriorCell(x, y)
                        if not cell then goto continue end

                        if data.availableCells and not data.availableCells[cell.id] then goto continue end

                        processCell(cell)

                        ::continue::
                    end
                end
            else
                local cell = world.getCellById(cellId)
                if cell then
                    processCell(cell)
                end
            end

            if not next(doors) then
                playerRef:sendEvent("AdvWMap:showMessage", l10n("NoLocationsForFastTravel"))
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
                    local destCell = types.Door.destCell(ref)
                    if (destCell.isExterior and not data.cellId) or destCell.id == data.cellId then
                        table.insert(interiorDoors, {ref = ref, dist = (ftDoorDestPos - ref.position):length()})
                    end
                end
            end

            if not next(interiorDoors) then
               playerRef:sendEvent("AdvWMap:showMessage", l10n("NoLocationsForFastTravel"))
                return
            end

            table.sort(interiorDoors, function (a, b)
                return a.dist < b.dist
            end)


            local targetDoor = interiorDoors[1].ref
            local isInSameInteriorBlock
            local depthToPoint = 0
            local distanceBetween = 0

            local function calcFastTravelInfo(targetCell, destCell)
                if isInSameInteriorBlock or targetCell.isExterior then return false end

                local exitsData, cells, exitCells, lowestDepth = cellLib.findExitPositions(targetCell)
                if cells and exitsData then
                    if cells[destCell.id] then
                        depthToPoint = cells[destCell.id]
                        isInSameInteriorBlock = true
                    else
                        isInSameInteriorBlock = false
                        depthToPoint = depthToPoint + lowestDepth
                    end

                    if next(exitsData) then
                        table.sort(exitsData, function (a, b)
                            return a.depth < b.depth
                        end)

                        return exitsData[1].pos
                    end
                end
            end

            local destCell = types.Door.destCell(targetDoor)
            local targetWorldPos
            local playerWorldPos

            if not destCell.isExterior then
                targetWorldPos = calcFastTravelInfo(destCell, playerRef.cell)
            else
                targetWorldPos = types.Door.destPosition(targetDoor)
            end
            if not isInSameInteriorBlock then
                if not playerRef.cell.isExterior then
                    playerWorldPos = calcFastTravelInfo(playerRef.cell, destCell)
                else
                    playerWorldPos = playerRef.position
                end
            end

            if targetWorldPos and playerWorldPos then
                distanceBetween = common.distance2D(targetWorldPos, playerWorldPos)
            end

            local message
            if cellId then
                local cellName = destCell.displayName or destCell.name or ""
                message = l10n("fastTravelMessageBoxMessage"):format(cellName)
            else
                local cellName = targetDoor.cell.displayName or targetDoor.cell.name or ""
                message = l10n("fastTravelMessageBoxMessage"):format(stringLib.getBeforeComma(cellName))
            end

            -- use the door object to send the position, because cell is not passed
            playerRef:sendEvent("AdvWMap:fastTravelMessage", {
                message = message,
                targetDoor = targetDoor,
                depthToPoint = depthToPoint,
                worldDistance = distanceBetween,
                isInSameInteriorBlock = isInSameInteriorBlock,
            })
        end,

        ["AdvWMap:fastTravelTeleport"] = function (data)
            if not data.targetDoor then return end

            local playerRef = world.players[1]

            playerRef:teleport(types.Door.destCell(data.targetDoor), types.Door.destPosition(data.targetDoor),
                {rotation = types.Door.destRotation(data.targetDoor), onGround = true})
            playerRef:sendEvent("AdvWMap:playSound", {soundId = "mysticism hit"})
            playerRef:sendEvent("AdvWMap:cancelAnimation", {groupName = "spellcast"})
            playerRef:sendEvent("AdvWMap:cancelAnimation", {groupName = "spellturnleft"})
            playerRef:sendEvent("AdvWMap:cancelAnimation", {groupName = "spellturnright"})
        end,

        ["AdvWMap:cellChanged"] = function ()
            local cell = world.players[1].cell

            if cell.isExterior then
                for x = -1, 1 do
                    for y = -1, 1 do
                        local c = world.getExteriorCell(cell.gridX + x, cell.gridY + y)
                        if c then
                            for _, ref in pairs(c:getAll(Door)) do
                                checkDoor(ref)
                            end
                        end
                    end
                end
            else
                for _, ref in pairs(cell:getAll(Door)) do
                    checkDoor(ref)
                end
            end
        end,

        ["AdvWMap:getMapStatics"] = function (data)
            local cellId = data.cellId or ""
            local cell = world.getCellById(cellId)
            if not cell then return end

            local res = {}
            for _, ref in pairs(cell:getAll(types.Static)) do
                local box = ref:getBoundingBox()
                local center = box.center
                local halfSize = box.halfSize
                local width = halfSize.x * 2
                local height = halfSize.y * 2
                if width < 128 or height < 128 then goto continue end
                table.insert(res, {center.x, center.y, width, height})
                ::continue::
            end
            world.players[1]:sendEvent("AdvWMap:getMapStatics", {res = res})
        end
    },
}