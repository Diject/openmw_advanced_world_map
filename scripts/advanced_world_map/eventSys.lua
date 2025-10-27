
local tableLib = require("scripts.advanced_world_map.utils.table")

local this = {}


this.events = {
    onMenuOpened = "onMenuOpened",
    onMapInitialized = "onMapInitialized",
    onMapShown = "onMapShown",
    onMarkerClick = "onMarkerClick",
    onMarkerClicked = "onMarkerClicked",
    onMarkerTooltipShow = "onMarkerTooltipShow",
    onMarkerTooltipShowed = "onMarkerTooltipShowed",
    onMapElementCreated = "onMapElementCreated",
    onMapElementRemoved = "onMapElementRemoved",
    onMousePress = "onMousePress",
    onMouseRelease = "onMouseRelease",
    onFocusLoss = "onFocusLoss",
    onMouseMove = "onMouseMove",
    onRightMouseMenu = "onRightMouseMenu",
    onResized = "onResized",
    onZoomed = "onZoomed",
}


this.handlers = {}

---@param eventId string
---@param handlerFunc fun(e : table)
function this.registerHandler(eventId, handlerFunc, priority)
    this.handlers[eventId] = this.handlers[eventId] or {}
    this.handlers[eventId][handlerFunc] = {handlerFunc, priority or 0}
end


---@param eventId string
---@param handlerFunc fun(e : table)
function this.unregisterHandler(eventId, handlerFunc)
    this.handlers[eventId] = this.handlers[eventId] or {}
    this.handlers[eventId][handlerFunc] = nil
end


---@param eventId string
---@return boolean
function this.isContainsHandler(eventId)
    return this.handlers[eventId] and next(this.handlers[eventId]) and true or false
end


---@param eventId string
---@return boolean? stopped
function this.triggerEvent(eventId, e)
    local handlerData = tableLib.values(this.handlers[eventId] or {}, function (a, b)
        return a[2] > b[2]
    end)

    local block = false
    for _, hData in ipairs(handlerData) do
        local cl, bl = hData[1](e or {})
        block = bl or block

        if cl then
            break
        end
    end

    return block
end

return this