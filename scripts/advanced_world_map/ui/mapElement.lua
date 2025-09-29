local util = require("openmw.util")

local this = {}


---@class advancedWorldMap.ui.mapElementMeta
local mapElementMeta = {}
mapElementMeta.__index = mapElementMeta


---@param val boolean
function mapElementMeta:setVisibility(val)
    self._elemLayout.props.visible = val
    self._params.visible = val
end

---@return boolean
function mapElementMeta:getVisibility()
    if self._params.visible == false then
        return false
    end
    return true
end

---@param val number [0, 1]
function mapElementMeta:setAlpha(val)
    self._elemLayout.props.alpha = val
    self._params.alpha = val
end

---@return number [0, 1]
function mapElementMeta:getAlpha()
    return self._params.alpha or 1
end

---@param val integer
function mapElementMeta:setSize(val)
    if self._params.text then
        self._params.fontSize = val
        self._elemLayout.userData.fontSize = val
        self._elemLayout.props.textSize = (self._params.scaleFunc or self._parent.scaleFunctions.marker)(val, self._parent.zoom)
    elseif self._params.texture then
        self._params.size = util.vector2(val, val)
        self._elemLayout.userData.size = self._params.size
        self._elemLayout.props.size = (self._params.scaleFunc or self._parent.scaleFunctions.marker)(self._params.size, self._parent.zoom)
    end
end

---@return integer|{x : number, y : number}
function mapElementMeta:getSize()
    if self._params.text then
        return self._params.fontSize
    elseif self._params.texture then
        return self._params.size
    end
    return 0
end

---@return number[]?
function mapElementMeta:getColor()
    if self._params.text then
        return self._elemLayout.props.textColor
    elseif self._params.texture then
        return self._elemLayout.props.color
    end
end

function mapElementMeta:setColor(color)
    if self._params.text then
        self._elemLayout.props.textColor = color
        self._params.color = color
    elseif self._params.texture then
        self._elemLayout.props.color = color
        self._params.color = color
    end
end


---@return string
function mapElementMeta:getId()
    return self._id
end

---@return integer
function mapElementMeta:getLayerId()
    return self._layerId
end


---@param parentMeta advancedWorldMap.ui.mapWidgetMeta
---@param elemParams advancedWorldMap.ui.mapWidgetMeta.createTextMarker.params|advancedWorldMap.ui.mapWidgetMeta.createImageMarker.params
---@return advancedWorldMap.ui.mapElementMeta
function this.new(parentMeta, id, layerId, elemParams, elemLayout)
    ---@class advancedWorldMap.ui.mapElementMeta
    local meta = setmetatable({}, mapElementMeta)

    meta._id = id
    meta._layerId = layerId
    meta._parent = parentMeta
    meta._params = elemParams
    meta._elemLayout = elemLayout

    return meta
end


return this