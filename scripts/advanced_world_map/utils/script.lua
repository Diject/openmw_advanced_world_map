local stringLib = require("scripts.advanced_world_map.utils.string")

local this = {}


---@param scriptText string
---@return table<string, any>|nil
function this.getShowMapPlaces(scriptText)
    local res = {}

    scriptText = stringLib.utf8_lower(scriptText)

    for line in scriptText:gmatch("[^\r\n]+") do
        if line:find("showmap", 1, true) and not line:match("^%s*;") then
            local place = line:match("^%s*showmap%s+\"([^\"]+)\"%s*$")
            if not place then
                place = line:match("^%s*showmap%s+(%S+)%s*$")
            end

            if place then
                res[place] = true
            end
        end
    end

    return next(res) and res or nil
end


return this