local types = require("openmw.types")
local core = require("openmw.core")
local world = require("openmw.world")

local protectedDoor = require("scripts.advanced_world_map.helpers.protectedDoor")

local stringLib = require("scripts.advanced_world_map.utils.string")
local tableLib = require("scripts.advanced_world_map.utils.table")
local commonData = require("scripts.advanced_world_map.common")

local l10n = core.l10n(commonData.l10nKey)

local Actor = types.Actor
local NPC = types.NPC
local Creature = types.Creature
local Container = types.Container
local Door = types.Door


local supportedTypes = {
    [types.NPC] = l10n("types.NPC"),
    [types.Creature] = l10n("types.Creature"),
    [types.Apparatus] = l10n("types.Apparatus"),
    [types.Armor] = l10n("types.Armor"),
    [types.Book] = l10n("types.Book"),
    [types.Clothing] = l10n("types.Clothing"),
    [types.Container] = l10n("types.Container"),
    [types.Ingredient] = l10n("types.Ingredient"),
    [types.Light] = l10n("types.Light"),
    [types.Lockpick] = l10n("types.Lockpick"),
    [types.Miscellaneous] = l10n("types.Miscellaneous"),
    [types.Potion] = l10n("types.Potion"),
    [types.Probe] = l10n("types.Probe"),
    [types.Repair] = l10n("types.Repair"),
    [types.Weapon] = l10n("types.Weapon"),
}


local this = {}


---@param text string
---@param params advancedWorldMap.helpers.search.objectPositions.params
---@return table<string, string>? objectNames
---@return table<any, number|boolean>? objectTypes
local function findObjectRecords(text, params)
    text = stringLib.utf8_lower(text)
    local hasEscapeCharacters = stringLib.hasEscapeCharacters(text)

    local objectNames = {}
    local objectTypes = {}

    local function findObjectIds(tp)
        if not tp.records then return end

        for _, rec in pairs(tp.records) do
            if params.byName ~= false and rec.name and (stringLib.utf8_lower(rec.name):find(text, 1, true) or
                    hasEscapeCharacters and stringLib.utf8_lower(rec.name):find(text)) then
                if not objectNames[rec.id] then
                    objectNames[rec.id] = rec.name
                    objectTypes[tp] = (objectTypes[tp] or 0) + 1
                end
            elseif params.byId and (rec.id:find(text, 1, true) or hasEscapeCharacters and rec.id:find(text)) then
                if not objectNames[rec.id] then
                    objectNames[rec.id] = rec.id
                    objectTypes[tp] = (objectTypes[tp] or 0) + 1
                end
            end
        end
    end

    if params.types then
        for _, typeKey in ipairs(params.types) do
            local type = types[typeKey]
            if type and supportedTypes[type] then
                findObjectIds(type)
            end
        end
    else
        for tp, _ in pairs(supportedTypes) do
            findObjectIds(tp)
        end
    end

    if params.inInventory then
        objectTypes[NPC] = objectTypes[NPC] or true
        objectTypes[Creature] = objectTypes[Creature] or true
        objectTypes[Container] = objectTypes[Container] or true
    end

    if not next(objectTypes) then return end
    return objectNames, objectTypes
end


---@param cellId string
---@return Cell[]
---@return table<string, boolean>
local function getNearbyCells(cellId)
    local res = {}
    local checked = {}

    local startingCell = world.getCellById(cellId)
    if not startingCell then return res, checked end

    local function fillDestinationCells(cell, destinationCells)
        checked[cell.id] = true
        for _, door in pairs(cell:getAll(Door)) do
            local destCell = Door.isTeleport(door) and protectedDoor.destCell(door) or nil
            if destCell and not destCell.isExterior and not checked[destCell.id] then
                table.insert(destinationCells, destCell)
                fillDestinationCells(destCell, destinationCells)
            end
        end
    end

    table.insert(res, startingCell)

    local destCells = {}

    if startingCell.isExterior then
        local gridX = startingCell.gridX
        local gridY = startingCell.gridY
        fillDestinationCells(startingCell, destCells)

        for i = -1, 1 do
            for j = -1, 1 do
                if i == 0 and j == 0 then goto continue end
                local cell = world.getExteriorCell(gridX, gridY)
                if not cell then goto continue end

                table.insert(res, cell)
                fillDestinationCells(cell, destCells)

                ::continue::
            end
        end

    else
        fillDestinationCells(startingCell, destCells)
    end

    for _, cell in ipairs(destCells) do
        table.insert(res, cell)
    end

    return res, checked
end


---@class advancedWorldMap.helpers.search.objectPositions.result
---@field id string
---@field name string
---@field type string
---@field locations {id: string?, pos: Vector3, owner: {id: string, name: string?, tp: string}?}[]

---@class advancedWorldMap.helpers.search.objectPositions.params
---@field text string
---@field types string[]?
---@field byId boolean? default: false
---@field byName boolean? default: true
---@field inInventory boolean? default: false
---@field limit number?
---@field startingCellId string?
---@field onlyNearby boolean?
---@field allowedCells table<string, any>?

---@alias advancedWorldMap.helpers.search.objectPositions.return table<string, advancedWorldMap.helpers.search.objectPositions.result>

---@param params advancedWorldMap.helpers.search.objectPositions.params
---@return advancedWorldMap.helpers.search.objectPositions.return?
function this.objectPositions(params)
    if not params or not params.text then return end
    params.limit = params.limit or 50

    ---@type advancedWorldMap.helpers.search.objectPositions.return
    local res = {}

    local objectNames, objectTypes = findObjectRecords(params.text, params)
    if not objectNames or not objectTypes then return end

    local objectCount = {}
    ---@type table<string, (table<string, {tp: string, name: string}>|boolean)?> by recordId
    local inventoryMap = {}

    local function removeSearchId(id, tpObj)
        objectNames[id] = nil
        if tpObj and type(objectTypes[tpObj]) == "number" then
            objectTypes[tpObj] = objectTypes[tpObj] - 1
            if objectTypes[tpObj] <= 0 then
                if not params.inInventory or (tpObj ~= NPC and tpObj ~= Creature and tpObj ~= Container) then
                    objectTypes[tpObj] = nil
                end
            end
        end
    end

    local index = 0

    local function processCell(cell)
        if params.allowedCells and not params.allowedCells[cell.id] then return end

        local function addToRes(recordId, tpName, pos, owner)
            local count = objectCount[recordId] or 0
            if count >= params.limit then return false end

            local recordData = res[recordId]
            if not recordData then
                recordData =  {
                    i = index,
                    id = recordId,
                    type = tpName,
                    name = objectNames[recordId],
                    locations = {}
                }
                index = index + 1
                res[recordId] = recordData
            end

            local ownerData
            if owner then
                ownerData = {
                    id = owner.recordId,
                    name = owner.type.record(owner).name,
                    tp = supportedTypes[owner.type] or "???"
                }
            end

            table.insert(recordData.locations, {id = not cell.isExterior and cell.id or nil, pos = pos, owner = ownerData})
            count = count + 1
            objectCount[recordId] = count

            return count < params.limit
        end


        for tp, _ in pairs(objectTypes) do
            local inventoryFunc = params.inInventory and (tp == NPC and NPC.inventory or
                tp == Creature and Creature.inventory or tp == Container and Container.inventory) or nil

            for _, ref in pairs(cell:getAll(tp)) do
                if not ref.enabled then goto continue end

                if inventoryFunc then
                    local inventory = inventoryFunc(ref)
                    local isResolved = inventory:isResolved()
                    local objectItems = nil
                    if not isResolved then
                        objectItems = inventoryMap[ref.recordId]
                    end

                    if objectItems == nil then
                        local own = nil
                        for _, item in pairs(inventory:getAll()) do
                            if objectNames[item.recordId] then
                                own = own or {}
                                own[item.recordId] = {name = objectNames[item.recordId], tp = item.type}
                            end
                        end
                        if not isResolved then
                            inventoryMap[ref.recordId] = own or false
                        end
                        objectItems = own
                    end

                    if objectItems then
                        for itemId, itemData in pairs(objectItems) do ---@diagnostic disable-line: param-type-mismatch
                            if not addToRes(itemId, supportedTypes[itemData.tp] or "???", ref.position, ref) then
                                objectItems[itemId] = nil
                                removeSearchId(itemId, itemData.tp)
                            end
                        end

                        if not next(objectItems) then ---@diagnostic disable-line: param-type-mismatch
                            inventoryMap[ref.recordId] = false
                        end
                    end
                end

                if not objectNames[ref.recordId] then goto continue end

                if not addToRes(ref.recordId, supportedTypes[tp], ref.position) then
                    removeSearchId(ref.recordId, tp)
                end

                ::continue::
            end
        end
    end

    local checkedCells = {}

    if params.startingCellId then
        local nearbyCells, checked = getNearbyCells(params.startingCellId)
        if nearbyCells then
            for _, cell in ipairs(nearbyCells) do
                processCell(cell)
            end
            checkedCells = checked
        end
    end

    if not params.onlyNearby then
        for _, cell in pairs(world.cells) do
            if not checkedCells[cell.id] then
                processCell(cell)
                if not next(objectNames) then
                    break
                end
            end
        end
    end

    return next(res) and res or nil
end


return this