local UI = require("openmw.interfaces").UI
local core = require("openmw.core")

local this = {}

this.essentialModes = {
    ["Interface"] = true,
    ["Dialogue"] = true,
    ["LevelUp"] = true,
    ["ChargenName"] = true,
    ["ChargenRace"] = true,
    ["ChargenBirth"] = true,
    ["ChargenClass"] = true,
    ["ChargenClassGenerate"] = true,
    ["ChargenClassReview"] = true,
    ["ChargenClassPick"] = true,
    ["ChargenClassCreate"] = true,
    ["MainMenu"] = true,
    ["Barter"] = true,
    ["SpellBuying"] = true,
    ["Travel"] = true,
}


local modeId = "Journal"
this.modeId = modeId

local activated = false


function this.activate()
    if this.isActive(true) then return end
    activated = true
    UI.addMode(modeId, {windows = {}})
end


function this.deactivate()
    if not activated then return end
    UI.removeMode(modeId)
    activated = false
end


function this.isActivated()
    return activated
end


function this.setActivatedFlag(val)
    activated = val and true or false
end


---@return boolean
function this.isActive(force)
    if not force and not activated then return false end
    for _, m in pairs(UI.modes) do
        if m == modeId then
            return true
        end
    end
    return false
end


---@return boolean
function this.isMenuInteractive()
    return UI.getMode() and true or false
end


---@param mode string?
function this.isModeActive(mode)
    if not mode then return false end
    for _, md in pairs(UI.modes) do
        if md == mode then
            return true
        end
    end
    return false
end


return this