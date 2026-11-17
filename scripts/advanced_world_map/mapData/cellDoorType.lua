local core = require("openmw.core")
local commonData = require("scripts.advanced_world_map.common")
local tableLib = require("scripts.advanced_world_map.utils.table")
local doorTypes = commonData.doorTypeId


local isMwscriptsSupported = core.mwscripts ~= nil


local this = {}


---@class advancedWorldMap.dynamicDataHandler.cellType.actorData
---@field guards table<string, any>
---@field pubOwners table<string, string|boolean>
---@field traderNPC table<string, integer>
---@field npcFaction table<string, string>

local houseFactions = {
    ["telvanni"] = doorTypes.telvanniHouse,
    ["redoran"] = doorTypes.redoranHouse,
    ["hlaalu"] = doorTypes.hlaaluHouse,
    ["t_mw_houseindoril"] = doorTypes.indorilHouse,
    ["t_mw_housedres"] = doorTypes.dresHouse,
    ["sixth house"] = doorTypes.dagothHouse,
}

local tradeServices = {
    -- Spells = true,
    -- Spellmaking = true,
    -- Enchanting = true,
    -- Training = true,
    -- Repair = true,
    Barter = true,
    Weapon = true,
    Armor = true,
    Clothing = true,
    Books = true,
    Ingredients = true,
    Picks = true,
    Probes = true,
    Lights = true,
    Apparatus = true,
    RepairItems = true,
    Misc = true,
    Potions = true,
    MagicItems = true,
    Travel = true,
}

local function getServiceCount(services)
    local count = 0
    for service, val in pairs(services) do
        if val and tradeServices[service] then
            count = count + 1
        end
    end
    return count
end


function this.fillActorRecordData(data, rec)
    if rec.class == "guard" then
        data.guards[rec.id] = true
    end

    if isMwscriptsSupported and rec.mwscript and rec.mwscript:find("pub", 1, true) then
        local scr = core.mwscripts.records[rec.mwscript]
        if scr and scr.text:find("rent == 1", 1, true) then
            data.pubOwners[rec.id] = rec.primaryFaction or true
        end
    end

    if rec.primaryFaction then
        data.npcFaction[rec.id] = rec.primaryFaction
    end

    local services = rec.servicesOffered
    local serviceCount = services and getServiceCount(services)
    local gold = rec.baseGold or 0
    local hasGold = gold >= 200
    if not services then
    elseif serviceCount > 6 then
        data.traderNPC[rec.id] = doorTypes.shop
    elseif services["Potions"] and serviceCount <= 5 and hasGold then
        data.traderNPC[rec.id] = doorTypes.alchemyShop
    elseif services["Picks"] and services["Probes"] and serviceCount <= 5 and hasGold then
        data.traderNPC[rec.id] = doorTypes.lockpickShop
    elseif services["Books"] and serviceCount <= 5 and hasGold then
        data.traderNPC[rec.id] = doorTypes.bookShop
    elseif services["Ingredients"] and serviceCount <= 5 and hasGold then
        data.traderNPC[rec.id] = doorTypes.ingredientShop
    elseif services["Clothing"] and serviceCount <= 6 and hasGold then
        data.traderNPC[rec.id] = doorTypes.clothingShop
    elseif services["Spells"] or services["Spellmaking"] or services["Enchanting"] then
        data.traderNPC[rec.id] = doorTypes.mageShop
    elseif services["Armor"] and serviceCount <= 6 and hasGold then
        data.traderNPC[rec.id] = doorTypes.armorShop
    elseif services["Weapon"] and serviceCount <= 6 and hasGold then
        data.traderNPC[rec.id] = doorTypes.weaponShop
    elseif services["Repair"] then
        data.traderNPC[rec.id] = doorTypes.repairShop
    elseif services["Training"] then
        data.traderNPC[rec.id] = doorTypes.trainerShop
    end
end


---@param cellId string
---@param actors any[]
---@param cellTypeData advancedWorldMap.dynamicDataHandler.cellType.actorData
---@return number?
function this.getCellType(cellId, actors, cellTypeData)
    local cellDoorType = nil
    local actorFullCount = #actors
    local npcCount = 0
    local nonTraderCount = 0
    local traderCount = 0
    local factionCount = 0
    local nonFactionCount = 0
    local traders = {}
    local factions = {}
    local isHouse = cellId:find(" house", 1, true) ~= nil
    for _, ref in pairs(actors) do
        if ref.enabled and not cellTypeData.guards[ref.recordId] then
            if cellTypeData.pubOwners[ref.recordId] then
                cellDoorType = doorTypes.pub
                if type(cellTypeData.pubOwners[ref.recordId]) ~= "string" then break end
            end

            local traderType = not isHouse and cellTypeData.traderNPC[ref.recordId] or nil
            if traderType then
                traders[traderType] = (traders[traderType] or 0) + 1
                traderCount = traderCount + 1
            else
                nonTraderCount = nonTraderCount + 1
            end

            local faction = cellTypeData.npcFaction[ref.recordId]
            if faction then
                factions[faction] = (factions[faction] or 0) + 1
                factionCount = factionCount + 1
            else
                nonFactionCount = nonFactionCount + 1
            end

            npcCount = npcCount + 1
        end
    end

    if factionCount >= 2 or npcCount == factionCount and actorFullCount > 3 then
        local topFaction
        local topCount = -math.huge
        for f, cnt in pairs(factions) do
            if cnt > topCount then
                topCount = cnt
                topFaction = f
            end
        end

        if topCount >= 2 and topCount > (npcCount - topCount) or
                topCount == factionCount then
            cellDoorType = houseFactions[topFaction] or doorTypes.faction
        end
    end

    if not cellDoorType and traderCount > 0 and traderCount > nonTraderCount then
        local cnt = tableLib.count(traders)
        if cnt == 1 then
            local tp = next(traders)
            cellDoorType = tp
        else
            cellDoorType = doorTypes.shop
        end
    end

    return cellDoorType
end


---@return integer?
function this.getHighPriorityDoorType(door)
    local recordId = door.recordId
    local record = door.type.record(recordId)
    local doorType
    if recordId:find("_dwrv", 1, true) or record.model and record.model:find("_dwrv", 1, true) then
        doorType = doorTypes.dwemer
    elseif recordId:find("_dae", 1, true) or record.model and record.model:find("_dae", 1, true) then
        doorType = doorTypes.daedra
    elseif recordId:find("_vault", 1, true) or record.model and record.model:find("_vault", 1, true) then
        doorType = doorTypes.vault
    end
    return doorType
end


---@return integer?
function this.getDoorType(door, doorDest)
    local destId = doorDest.id
    local recordId = door.recordId
    local record = door.type.record(recordId)
    local doorType
    if destId:find(" mine", 1, true) then
        doorType = doorTypes.mine
    elseif recordId:find("_cave", 1, true) or record.model and (record.model:find("_cave", 1, true) or
            record.model:find("_pelt", 1, true) or record.model:find("_dark", 1, true) or
            record.model:find("_black", 1, true)) or destId:find("cave", 1, true) then
        doorType = doorTypes.cave
    elseif recordId:find("_tomb", 1, true) or record.model and record.model:find("_tomb", 1, true) or
            destId:find(" tomb", 1, true) or recordId:find("barrow", 1, true) or destId:find(" barrow", 1, true) or
            destId:find(" crypt", 1, true) then
        doorType = doorTypes.tomb
    elseif recordId:find("_ashl", 1, true) or record.model and record.model:find("_ashl", 1, true) or
            destId:find(" yurt", 1, true) then
        doorType = doorTypes.ashlander
    elseif recordId:find("_ship", 1, true) or record.model and record.model:find("_ship", 1, true) then
        doorType = doorTypes.ship
    elseif destId:find("fort", 1, true) or destId:find("tower", 1, true) then
        doorType = doorTypes.fort
    elseif destId:find(" smith", 1, true) then
        doorType = doorTypes.repairShop
    elseif destId:find(" clothier", 1, true) then
        doorType = doorTypes.clothingShop
    elseif destId:find(" armorer", 1, true) then
        doorType = doorTypes.armorShop
    elseif destId:find(" pawnbroker", 1, true) or destId:find(" trader", 1, true) then
        doorType = doorTypes.clothingShop
    elseif destId:find(" enchanter", 1, true) then
        doorType = doorTypes.mageShop
    elseif destId:find(" alchemist", 1, true) then
        doorType = doorTypes.alchemyShop
    end

    return doorType
end


---@return integer?
function this.getDestDoorType(destId)
    local doorType
    if destId:find(" mine", 1, true) then
        doorType = doorTypes.mine
    elseif destId:find("cave", 1, true) then
        doorType = doorTypes.cave
    elseif destId:find(" tomb", 1, true) or destId:find(" barrow", 1, true) or
            destId:find(" crypt", 1, true) then
        doorType = doorTypes.tomb
    elseif destId:find("fort", 1, true) then
        doorType = doorTypes.fort
    elseif destId:find(" smith", 1, true) then
        doorType = doorTypes.repairShop
    end

    return doorType
end


return this