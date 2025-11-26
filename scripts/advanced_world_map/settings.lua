local I = require("openmw.interfaces")
local ui = require('openmw.ui')
local util = require('openmw.util')
local input = require('openmw.input')
local storage = require('openmw.storage')

local config = require("scripts.advanced_world_map.config.config")
local commonData = require("scripts.advanced_world_map.common")

I.Settings.registerPage{
  key = commonData.settingPage,
  l10n = commonData.l10nKey,
  name = "modName",
  description = "modDescription",
}

---@class questGuider.settings.boolSetting
---@field key string
---@field name string l10n
---@field description string|nil l10n
---@field default boolean|nil
---@field trueLabel string|nil
---@field falseLabel string|nil
---@field disabled boolean|nil

---@class questGuider.settings.numberSetting
---@field key string
---@field name string l10n
---@field description string|nil l10n
---@field default number|nil
---@field min number|nil
---@field max number|nil
---@field integer boolean|nil
---@field disabled boolean|nil

---@class questGuider.settings.label
---@field description string|nil l10n
---@field disabled boolean|nil

---@class questGuider.settings.text
---@field text string|nil
---@field disabled boolean|nil


---@param args questGuider.settings.boolSetting
local function boolSetting(args)
    return {
        key = args.key,
        renderer = "checkbox",
        name = args.name,
        description = args.description,
        default = args.default or false,
        argument = {
            trueLabel = args.trueLabel,
            falseLabel = args.falseLabel,
            disabled = args.disabled,
        }
    }
end

---@param args questGuider.settings.numberSetting
local function numberSetting(args)
    local data = {
        key = args.key,
        renderer = "number",
        name = args.name,
        description = args.description,
        default = args.default or 0,
        argument = {
            min = args.min,
            max = args.max,
            integer = args.integer,
            disabled = args.disabled,
        }
    }
    return data
end

local lableId = 0
---@param args questGuider.settings.label
local function textLabel(args)
    local data = {
        renderer = "QGL:Renderer:label",
        key = "__dummy__"..tostring(lableId),
        name = "empty",
        description = args.description,
        disabled = args.disabled,
    }
    lableId = lableId + 1
    return data
end

local function text(args)
    local data = {
        renderer = "QGL:Renderer:text",
        key = "__dummy__"..tostring(lableId),
        name = "empty",
        description = args.description,
        disabled = args.disabled,
        text = args.text,
    }
    lableId = lableId + 1
    return data
end


local function inputKey(args)
    local data = {
        renderer = "AdvWMap:inputBinding",
        key = args.key,
        name = args.name,
        description = args.description,
        default = args.default,
        argument = {
            action = args.action
        }
    }
    return data
end

local function color(args)
    local data = {
        renderer = "color",
        key = args.key,
        name = args.name,
        description = args.description,
        default = args.default,
        argument = {
            disabled = args.disabled,
        }
    }
    return data
end



I.Settings.registerGroup{
    key = commonData.configMainSectionName,
    page = commonData.settingPage,
    l10n = commonData.l10nKey,
    name = "Main",
    permanentStorage = true,
    order = 0,
    settings = {
        inputKey{key = "main.menuKey", name = "customJournalKeyName", description = "customJournalKeyDescription", action = commonData.menuKeyId, default = config.default.main.menuKey},
    },
}