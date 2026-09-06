local this = {}


this.data = {}


function this.get(cellId)
    return this.data[cellId or ""]
end


function this.set(cellId, yaw)
    this.data[cellId] = yaw
end


return this