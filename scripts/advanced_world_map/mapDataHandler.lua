local vfs = require("openmw.vfs")
local markup = require("openmw.markup")
local core = require("openmw.core")
local ui = require("openmw.ui")

local log = require("scripts.advanced_world_map.utils.log")

local commonData = require("scripts.advanced_world_map.common")

local config = require("scripts.advanced_world_map.config.config")


---@class advancedWorldMap.mapImageInfo
---@field version integer
---@field time integer
---@field file string
---@field width integer
---@field height integer
---@field pixelsPerCell integer
---@field gridX {min : integer, max : integer}
---@field gridY {min : integer, max : integer}

local this = {}


---@type string
this.mapImagePath = nil
---@type advancedWorldMap.mapImageInfo?
this.mapInfo = nil

this.localMapTextureCache = {}


---@return string?
---@return advancedWorldMap.mapImageInfo?
local function getMapImage(dirPath)
    local mapInfo
    local imagePath

    local mapInfoPath = dirPath.."mapInfo.yaml"

    if vfs.fileExists(mapInfoPath) then
        local s, res = pcall(function ()
            mapInfo = markup.loadYaml(mapInfoPath)
            local path = dirPath..mapInfo.file
            if vfs.fileExists(path) then
                imagePath = path
            end
        end)
    else
        return
    end

    return imagePath, mapInfo
end


---@return boolean
local function initMapImage(initializerType)
    local imagePath, mapInfo

    if initializerType == commonData.dataInitializerTypes[2] then
        imagePath, mapInfo = getMapImage(commonData.customMapDir)
    elseif initializerType == commonData.dataInitializerTypes[3] then
        imagePath, mapInfo = getMapImage(commonData.questDataMapDir)
    elseif initializerType == commonData.dataInitializerTypes[4] then
        imagePath, mapInfo = getMapImage(commonData.defaultTRMapDir)
    elseif initializerType == commonData.dataInitializerTypes[5] then
        imagePath, mapInfo = getMapImage(commonData.defaultBaseMapDir)
    elseif initializerType == commonData.dataInitializerTypes[1] then
        for i, initializer in ipairs(commonData.dataInitializerTypes) do
            if i == 1 then goto continue end
            local res = initMapImage(initializer)
            if res then
                return true
            end
            ::continue::
        end
    end

    if imagePath and mapInfo then
        this.mapImagePath = imagePath
        this.mapInfo = mapInfo
        log("Map image initialized from: "..imagePath)
        return true
    end
    return false
end


function this.init()
    if initMapImage(config.data.data.initializer) then
        return true
    end

    if initMapImage(commonData.dataInitializerTypes[1]) then
        return true
    end

    log("No valid map image found")
    this.mapImagePath = nil
    this.mapInfo = nil
    return false
end



function this.getLocalMapTexture(gridX, gridY)
    local path = string.format("%s%d,%d.png", commonData.localMapTexturesDir, gridX, gridY)

    if this.localMapTextureCache[path] then return this.localMapTextureCache[path] end

    if not vfs.fileExists(path) then return end

    local texture = ui.texture{ path = path }
    this.localMapTextureCache[path] = texture

    return texture
end


return this