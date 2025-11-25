local vfs = require("openmw.vfs")
local markup = require("openmw.markup")
local core = require("openmw.core")
local ui = require("openmw.ui")
local util = require("openmw.util")

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

---@class advancedWorldMap.localCellInfo
---@field mX integer?
---@field mY integer
---@field nA number
---@field width integer
---@field height integer

local this = {}


---@type string
this.mapImagePath = nil
---@type advancedWorldMap.mapImageInfo?
this.mapInfo = nil

this.localMapTextureCache = {}

this.localCellTextureCache = {}

---@type table<string, advancedWorldMap.localCellInfo>
this.localCellInfo = {}


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
    local path = string.format("%s(%d,%d)", commonData.localMapTexturesDir, gridX, gridY)
    local pathPng = path..".png"
    local pathTga = path..".tga"

    if this.localMapTextureCache[path] then return this.localMapTextureCache[path] end

    local foundPath
    if vfs.fileExists(pathPng) then
        foundPath = pathPng
    elseif vfs.fileExists(pathTga) then
        foundPath = pathTga
    else
        return
    end

    local texture = ui.texture{ path = foundPath }
    this.localMapTextureCache[path] = texture

    return texture
end


function this.getLocalCellInfo(cellId)
    if this.localCellInfo[cellId] then
        return this.localCellInfo[cellId]
    end

    local path = string.format("%s%s.yaml", commonData.localMapTexturesDir, cellId:gsub(":", ""))
    if not vfs.fileExists(path) then
        this.localCellInfo[cellId] = {} ---@diagnostic disable-line: missing-fields
    else
        this.localCellInfo[cellId] = markup.loadYaml(path)
    end

    return this.localCellInfo[cellId]
end


function this.getLocalCellMapTextures(cellId)
    if this.localCellTextureCache[cellId] then
        return this.localCellTextureCache[cellId]
    end

    local cellInfo = this.getLocalCellInfo(cellId)
    if not cellInfo.mX then return end

    local res = {}
    for y = 1, cellInfo.height do
        local arr = {}
        for x = 1, cellInfo.width do
            local path = string.format("%s%s [%d,%d]", commonData.localMapTexturesDir, cellId:gsub(":", ""), x - 1, y - 1)
            local pathPng = path..".png"
            local pathTga = path..".tga"

            local foundPath
            if vfs.fileExists(pathPng) then
                foundPath = pathPng
            elseif vfs.fileExists(pathTga) then
                foundPath = pathTga
            else
                goto continue
            end

            local texture = ui.texture{ path = foundPath, offset = util.vector2(1, 1), size = util.vector2(254, 254) }
            arr[x] = texture

            ::continue::
        end
        res[y] = arr
    end

    this.localCellTextureCache[cellId] = res
    return res
end


return this