
local this = {}


this.data = {}
---@type table<string, advancedWorldMap.input.hotkeyLayers.register.params> by id
this.current = {}


---@class advancedWorldMap.input.hotkeyLayers.register.params
---@field id string
---@field group string?
---@field priority number?
---@field activateFun fun()?
---@field deactivateFun fun()?


---@param params advancedWorldMap.input.hotkeyLayers.register.params
function this.register(params)
    this.deactivate(params.id)

    params.priority = params.priority or 0
    params.group = params.group or "_default_"
    this.data[params.id] = params

    this.update(params.group)
end


---@param id string
function this.unregister(id)
    local dt = this.deactivate(id)

    if dt then
        this.data[id] = nil

        this.update(dt.group)
    end
end


local function deactivateGroup(group)
    for id, dt in pairs(this.current) do
        if dt.group == group then
            this.deactivate(id)
            this.current[id] = nil
        end
    end
end


function this.update(group)
    local maxV = -math.huge
    for id, dt in pairs(this.data) do
        if dt.group == group and maxV < dt.priority then
            maxV = dt.priority
        end
    end

    deactivateGroup(group)

    if maxV == -math.huge then return end

    for id, dt in pairs(this.data) do
        if dt.group == group and maxV == dt.priority then
            this.current[id] = dt
            this.activate(dt.id)
        end
    end
end


function this.activate(id)
    local dt = this.data[id]
    if dt and dt.activateFun then
        dt.activateFun()
        this.current[id] = dt
    end
end


function this.deactivate(id)
    local dt = this.data[id]
    if dt and this.current[id] then
        if dt.deactivateFun then
            dt.deactivateFun()
        end
        this.current[id] = nil
    end
    return dt
end


function this.isActive(id)
    return this.current[id] ~= nil
end


function this.reset()
    for id, dt in pairs(this.current) do
        this.deactivate(id)
        this.current[id] = nil
    end
    for id, dt in pairs(this.data) do
        this.data[id] = nil
    end
end


return this