local input = require("openmw.input")
local core = require("openmw.core")

local common = require("scripts.advanced_world_map.common")
local config = require("scripts.advanced_world_map.config.config")

local l10n = core.l10n(common.l10nKey)


local this = {}


this.isGamepad = true


this.keyName = {
    ["LMB"] = l10n("leftMouseButton"),
    ["MMB"] = l10n("middleMouseButton"),
    ["RMB"] = l10n("rightMouseButton"),
    ["MB4"] = l10n("mouseButton4"),
    ["MB5"] = l10n("mouseButton5"),
    ["C_A"] = "A",
    ["C_B"] = "B",
    ["C_X"] = "X",
    ["C_Y"] = "Y",
    ["C_Back"] = "Back",
    ["C_Guide"] = "Guide",
    ["C_Start"] = "Start",
    ["C_LeftStick"] = "Left Stick Btn",
    ["C_RightStick"] = "Right Stick Btn",
    ["C_LeftShoulder"] = "LB",
    ["C_RightShoulder"] = "RB",
    ["C_DPadUp"] = "D-pad Up",
    ["C_DPadDown"] = "D-pad Down",
    ["C_DPadLeft"] = "D-pad Left",
    ["C_DPadRight"] = "D-pad Right",
    ["C_DPAD"] = "D-pad",
    ["C_RT"] = "RT",
    ["C_LT"] = "LT",
    ["C_LSTICK"] = "Left Stick",
    ["C_RSTICK"] = "Right Stick",
}

this.keyImage = {
    ["C_A"] = "textures/omw_steam_button_a.dds",
    ["C_B"] = "textures/omw_steam_button_b.dds",
    ["C_X"] = "textures/omw_steam_button_x.dds",
    ["C_Y"] = "textures/omw_steam_button_y.dds",
    ["C_Back"] = "textures/omw_steam_button_view.dds",
    ["C_Start"] = "textures/omw_steam_button_menu.dds",
    ["C_LeftStick"] = "textures/omw_steam_button_l3.dds",
    ["C_RightStick"] = "textures/omw_steam_button_r3.dds",
    ["C_LeftShoulder"] = "textures/omw_xbox_button_lb.dds",
    ["C_RightShoulder"] = "textures/omw_xbox_button_rb.dds",
    -- ["C_DPadUp"] = "textures/omw_steam_button_dpad.dds",
    -- ["C_DPadDown"] = "textures/omw_steam_button_dpad.dds",
    -- ["C_DPadLeft"] = "textures/omw_steam_button_dpad.dds",
    -- ["C_DPadRight"] = "textures/omw_steam_button_dpad.dds",

    ["C_DPAD"] = "textures/omw_steam_button_dpad.dds",
    ["C_RT"] = "textures/omw_xbox_button_rt.dds",
    ["C_LT"] = "textures/omw_xbox_button_lt.dds",
    ["C_LSTICK"] = "textures/omw_steam_button_lstick.dds",
    ["C_RSTICK"] = "textures/omw_steam_button_rstick.dds",
}


local dpadBtns = {
    ["C_DPadUp"] = true,
    ["C_DPadDown"] = true,
    ["C_DPadLeft"] = true,
    ["C_DPadRight"] = true,
}

function this.isDpadBtn(btn)
    return dpadBtns[btn] or false
end


function this.splitKeyCombination(comb)
    local keys = {}
    for key in string.gmatch(comb, "[^%s%+]+") do
        table.insert(keys, key)
    end
    return keys
end


---@param combination string?
---@return string?
function this.keyCombinationToString(combination)
    if not combination then return end

    local keys = this.splitKeyCombination(combination)
    local keyNames = {}
    for _, key in ipairs(keys) do
        local name
        local isKey, keyId = pcall(function ()
            return input.KEY[key]
        end)
        if isKey and keyId then
            name = input.getKeyName(keyId)
        else
            name = this.keyName[key]
        end
        name = name or key

        table.insert(keyNames, name)
    end

    return table.concat(keyNames, " + ")
end


function this.isKeyValidToShow(comb)
    if not comb then return false end
    local hasGamepadKey = comb:find("C_") and true or false
    return this.isGamepad == hasGamepadKey
end



return this