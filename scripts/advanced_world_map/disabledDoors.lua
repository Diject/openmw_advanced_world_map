local storage = require("scripts.advanced_world_map.storage.localStorage")
local commonData = require("scripts.advanced_world_map.common")

local this = {}


this.doorHashTable = {}


function this.register(id)
    this.doorHashTable[id] = true
end


function this.unregister(id)
    this.doorHashTable[id] = nil
end


function this.contains(id)
    return this.doorHashTable[id] ~= nil
end


function this.init()
    this.doorHashTable = storage.data[commonData.disabledDoorsFieldId] or {}
end


return this