local util = require("openmw.util")
local ui = require("openmw.ui")
local async = require("openmw.async")
local core = require("openmw.core")
local I = require("openmw.interfaces")

local commonData = require("scripts.advanced_world_map.common")
local eventSys = require("scripts.advanced_world_map.eventSys")
local config = require("scripts.advanced_world_map.config.configLib")
local templates = require("scripts.advanced_world_map.ui.templates")
local hotkeyLayers = require("scripts.advanced_world_map.input.hotkeyLayers")
local keysModule = require("scripts.advanced_world_map.input.keys")

local menuHandler = require("scripts.advanced_world_map.menuHandler")
local menuMode = require("scripts.advanced_world_map.ui.menuMode")

local l10n = core.l10n(commonData.l10nKey)


local this = {}

this.menu = nil
this.items = nil
this.index = 0


---@class advancedWorldMap.ui.quickMenu.item
---@field text string
---@field onClick function?

---@class advancedWorldMap.ui.quickMenu.create.params
---@field menu advancedWorldMap.ui.menu.map
---@field items advancedWorldMap.ui.quickMenu.item[]


local directionHotkeyFuncs = {}
for i = 1, 2 do
    directionHotkeyFuncs[i] = function ()
        if not menuMode.isMenuInteractive() or not menuHandler.getMenu(commonData.mapMenuId) then return end

        if i == 1 then
            this.select(this.index - 1)
        else
            this.select(this.index + 1)
        end
    end
end

local function clickOnSelected()
    if not menuMode.isMenuInteractive() then return end
    this.clickOnSelected()
end

local function registerHotkeys()
    I.DijectKeyBindings.action.register(commonData.topMarkerKeyId, directionHotkeyFuncs[1])
    if I.DijectKeyBindings.getActionKey(commonData.topMarkerKeyId) == config.default.input.topMarkerHotkey then
        I.DijectKeyBindings.keybind.register("UpArrow", directionHotkeyFuncs[1])
    end
    I.DijectKeyBindings.action.register(commonData.bottomMarkerKeyId, directionHotkeyFuncs[2])
    if I.DijectKeyBindings.getActionKey(commonData.bottomMarkerKeyId) == config.default.input.bottomMarkerHotkey then
        I.DijectKeyBindings.keybind.register("DownArrow", directionHotkeyFuncs[2])
    end

    I.DijectKeyBindings.keybind.register("C_A", clickOnSelected)
    I.DijectKeyBindings.keybind.register("Enter", clickOnSelected)
end

local function unregisterHotkeys()
    I.DijectKeyBindings.action.unregister(commonData.topMarkerKeyId, directionHotkeyFuncs[1])
    I.DijectKeyBindings.action.unregister(commonData.bottomMarkerKeyId, directionHotkeyFuncs[2])

    I.DijectKeyBindings.keybind.unregister("UpArrow", directionHotkeyFuncs[1])
    I.DijectKeyBindings.keybind.unregister("DownArrow", directionHotkeyFuncs[2])

    I.DijectKeyBindings.keybind.unregister("C_A", clickOnSelected)
    I.DijectKeyBindings.keybind.unregister("Enter", clickOnSelected)
end


---@param params advancedWorldMap.ui.quickMenu.create.params
local function create(params)
    this.destroy()

    local menu = params.menu
    local mapWidget = menu.mapWidget

    local pos = mapWidget.screenPosition + util.vector2(0, mapWidget.layout.props.size.y)

    local content = ui.content{}

    for i, item in ipairs(params.items) do
        local lay = {
            template = templates.quickMenuItem,
            props = {
                inheritAlpha = false,
            },
            userData = item,
            events = {
                mouseClick = async:callback(function(e, layout)
                    if item.onClick then
                        item.onClick()
                    end
                    this.destroy()
                end),

                focusLoss = async:callback(function(e, layout)
                    this.index = 0
                    if layout.template ~= templates.quickMenuItem then
                        this.select()
                    end
                end),

                mouseMove = async:callback(function(e, layout)
                    this.index = i
                    if layout.template ~= templates.quickMenuSelectedItem then
                        this.select(i)
                    end
                end),
            },
            content = ui.content{
                {
                    type = ui.TYPE.Text,
                    props = {
                        text = item.text,
                        textSize = math.floor(config.data.ui.fontSize * 0.7) * 2,
                        textColor = config.data.ui.defaultColor,
                        autoSize = false,
                        size = util.vector2(250, math.floor(config.data.ui.fontSize * 0.8) * 2 + 4),
                        multiline = true,
                        wordWrap = true,
                        textAlignH = ui.ALIGNMENT.Center,
                        textAlignV = ui.ALIGNMENT.Center,
                    },
                }
            }
        }

        content:add(lay)
    end

    local lay = {
        template = templates.boxSolid,
        layer = commonData.messageLayer,
        name = commonData.quickMenuId,
        props = {
            position = pos,
            alpha = 0.75,
            inheritAlpha = false,
            anchor = util.vector2(0, 1),
        },
        content = ui.content{
            {
                type = ui.TYPE.Flex,
                props = {
                    autoSize = true,
                },
                content = content,
            }
        }
    }

    this.menu = ui.create(lay)
end


function this.update()
    if this.menu and this.menu.layout then
        this.menu:update()
    end
end


function this.isExists()
    return this.menu and this.menu.layout and true or false
end


function this.destroy()
    if not this.menu then return end

    if this.menu.layout then
        this.menu:destroy()
    end

    this.menu = nil
    this.items = nil
    this.index = 0

    hotkeyLayers.unregister(commonData.hotkeyLayerQuickMenu)
end


---@param pos integer?
function this.select(pos)
    if not this.menu or not this.menu.layout then return end

    local content = this.menu.layout.content[1].content
    local contentCount = #content

    if pos then
        if pos < 1 then
            pos = contentCount
        end
        if pos > contentCount then
            pos = 1
        end
    else
        pos = 0
    end

    for i, el in ipairs(content) do
        if i == pos then
            el.template = templates.quickMenuSelectedItem
            this.index = i
        else
            el.template = templates.quickMenuItem
        end
    end

    this.menu:update()
end


function this.clickOnSelected()
    if not this.menu or not this.menu.layout or this.index == 0 then return end

    local content = this.menu.layout.content[1].content
    local contentCount = #content
    if this.index > contentCount or this.index < 1 then return end

    local elem = content[this.index]
    elem.events.mouseClick()
end


---@param parentMenu advancedWorldMap.ui.menu.map
function this.create(parentMenu)

    ---@type advancedWorldMap.ui.quickMenu.item[]
    local items = {}

    eventSys.triggerEvent(eventSys.EVENT.onQuickMenu, {menu = parentMenu, items = items, module = this})

    table.insert(items, {
        text = l10n("QuickMenuBack"),
        onClick = function () end
    })

    create({menu = parentMenu, items = items})

    hotkeyLayers.register{
        id = commonData.hotkeyLayerQuickMenu,
        priority = 200,
        activateFun = registerHotkeys,
        deactivateFun = unregisterHotkeys,
    }

    if keysModule.isGamepad then
        this.select(1)
    end
end



return this