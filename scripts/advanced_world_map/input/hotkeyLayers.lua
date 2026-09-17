
local this = {}


this.data = {}
this.currentId = nil


---@class advancedWorldMap.input.hotkeyLayers.register.params
---@field id string
---@field priority number?
---@field activateFun fun()
---@field deactivateFun fun()


---@param params advancedWorldMap.input.hotkeyLayers.register.params
function this.register(params)
    this.deactivate(params.id)

    params.priority = params.priority or 0
    this.data[params.id] = params

    this.update()
end


---@param id string
function this.unregister(id)
    this.deactivate(id)

    this.data[id] = nil

    this.update()
end


function this.update()
    local maxV = -math.huge
    local maxId
    for id, dt in pairs(this.data) do
        if maxV < dt.priority then
            maxId = id
            maxV = dt.priority
        end
    end

    if this.currentId == maxId then return end

    if this.currentId then
        this.deactivate(this.currentId)
        this.currentId = nil
    end
    if maxId then
        this.currentId = maxId
        this.activate(maxId)
    end
end


function this.activate(id)
    local dt = this.data[id]
    if dt and dt.activateFun then
        dt.activateFun()
    end
end


function this.deactivate(id)
    local dt = this.data[id]
    if dt and id == this.currentId and dt.deactivateFun then
        dt.deactivateFun()
    end
end


function this.reset()
    if this.currentId then
        this.deactivate(this.currentId)
        this.currentId = nil
    end
    for id, dt in pairs(this.data) do
        this.data[id] = nil
    end
end


return this