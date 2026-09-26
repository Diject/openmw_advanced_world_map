local util = require("openmw.util")
local ui = require("openmw.ui")
local I = require("openmw.interfaces")

local commonData = require("scripts.advanced_world_map.common")
local eventSys = require("scripts.advanced_world_map.eventSys")
local config = require("scripts.advanced_world_map.config.config")
local uiUtils = require("scripts.advanced_world_map.ui.utils")
local realTimer = require("scripts.advanced_world_map.realTimer")
local menuMode = require("scripts.advanced_world_map.ui.menuMode")
local menuHandler = require("scripts.advanced_world_map.menuHandler")
local hotkeyLayers = require("scripts.advanced_world_map.input.hotkeyLayers")
local keysModule = require("scripts.advanced_world_map.input.keys")

local templates = require("scripts.advanced_world_map.ui.templates")


local this = {}

this.menu = nil
this.selectedItemIndex = 0


local directionHotkeyFuncs = {}
for i = 1, 2 do
    directionHotkeyFuncs[i] = function ()
        if not menuMode.isMenuInteractive() or not menuHandler.getMenu(commonData.mapMenuId) then return end

        if i == 1 then
            this.selectItem(this.selectedItemIndex - 1)
        else
            this.selectItem(this.selectedItemIndex + 1)
        end
    end
end


local function registerHotkeys()
    I.DijectKeyBindings.action.register(commonData.topMarkerKeyId, directionHotkeyFuncs[1])
    -- if I.DijectKeyBindings.getActionKey(commonData.topMarkerKeyId) == config.default.input.topMarkerHotkey then
    --     I.DijectKeyBindings.keybind.register("UpArrow", directionHotkeyFuncs[1])
    -- end
    I.DijectKeyBindings.action.register(commonData.bottomMarkerKeyId, directionHotkeyFuncs[2])
    -- if I.DijectKeyBindings.getActionKey(commonData.bottomMarkerKeyId) == config.default.input.bottomMarkerHotkey then
    --     I.DijectKeyBindings.keybind.register("DownArrow", directionHotkeyFuncs[2])
    -- end

    I.DijectKeyBindings.keybind.register("C_A", this.clickOnSelectedItem)
    -- I.DijectKeyBindings.keybind.register("Enter", this.clickOnSelectedItem)
end

local function unregisterHotkeys()
    I.DijectKeyBindings.action.unregister(commonData.topMarkerKeyId, directionHotkeyFuncs[1])
    I.DijectKeyBindings.action.unregister(commonData.bottomMarkerKeyId, directionHotkeyFuncs[2])

    -- I.DijectKeyBindings.keybind.unregister("UpArrow", directionHotkeyFuncs[1])
    -- I.DijectKeyBindings.keybind.unregister("DownArrow", directionHotkeyFuncs[2])

    I.DijectKeyBindings.keybind.unregister("C_A", this.clickOnSelectedItem)
    -- I.DijectKeyBindings.keybind.unregister("Enter", this.clickOnSelectedItem)
end


---@param mapWidget advancedWorldMap.ui.mapWidgetMeta
function this.openMenu(mapWidget)
    if this.menu and this.menu.layout then
        this.menu:destroy()
        this.menu = nil
    end

    if not menuMode.isMenuInteractive() then
        return
    end

    if eventSys.isContainsHandler(eventSys.EVENT["onRightMouseMenu"]) then
        local pos = mapWidget:getScreenPositionOfCursor()
        local lay = {
            layer = commonData.messageLayer,
            name = commonData.rightClickMenuId,
            type = ui.TYPE.Flex,
            props = {
                autoSize = true,
                position = pos,
                anchor = util.vector2(0, 0),
                propagateEvents = false,
            },
            content = ui.content{

            },
        }

        local marker = mapWidget.layout.userData.lastMarkerElement
        marker = marker and marker:isValid() and marker or nil

        local layContent = lay.content
        eventSys.triggerEvent(eventSys.EVENT["onRightMouseMenu"], {
            mapWidget = mapWidget,
            relPos = mapWidget:getRelativePositionOfCursor(),
            content = layContent,
            marker = marker,
        })

        if #layContent > 0 then
            for i, l in ipairs(layContent) do
                layContent[i] = {
                    template = templates.inactiveSelection,
                    content = ui.content{l}
                }
            end
            this.menu = ui.create(lay)

            hotkeyLayers.register{
                id = commonData.hotkeyLayerContextMenu,
                priority = 300,
                activateFun = registerHotkeys,
                deactivateFun = unregisterHotkeys,
            }
        end

        this.selectedItemIndex = 0
        if keysModule.isGamepad and this.menu then
            this.selectItem(1)
        end
    end
end


function this.closeMenu()
    if not this.menu or not this.menu.layout then return end
    this.menu:destroy()
    this.menu = nil
    this.selectedItemIndex = 0
    hotkeyLayers.unregister(commonData.hotkeyLayerContextMenu)
end


function this.hasMenu()
    if not this.menu or not this.menu.layout then return false end
    return true
end


function this.update()
    if this.menu and this.menu.layout then
        this.menu:update()
    end
end


local function resetSelection(content)
    for i, lay in ipairs(content) do
        if lay.template and lay.template == templates.activeSelection then
            lay.template = templates.inactiveSelection
        end
    end
end


---@param index integer?
function this.selectItem(index)
    if not this.menu or not this.menu.layout then return false end

    local content = this.menu.layout.content
    local itemCount = #content

    resetSelection(content)

    if itemCount < 1 then return false end

    local p = index or (this.selectedItemIndex + 1)
    if p > itemCount then
        p = 1
    elseif p < 1 then
        p = itemCount
    end

    content[p].template = templates.activeSelection
    this.selectedItemIndex = p
    this.update()

    return true
end


function this.clickOnSelectedItem()
    if not this.menu or not this.menu.layout then return false end

    local menuLayout = this.menu.layout
    local content = menuLayout.content
    local item = uiUtils.getFromContent(content, this.selectedItemIndex)
    if not item or not item.content then return false end

    item = uiUtils.getFromContent(item.content, 1)
    if not item or not item.events then return false end

    local events = item.events

    local itemSize = item.props and item.props.size
    local offset = itemSize and util.vector2(math.floor(itemSize.x * 0.5), math.floor(itemSize.y * 0.5)) or util.vector2(1, 1)
    local position = menuLayout.props.position + offset

    if not events.mouseClick and not events.mousePress and not events.mouseRelease then return false end

    if events.mouseMove then
        events.mouseMove({offset = offset, position = position}, item)
    end

    if events.focusGain then
        events.focusGain(nil, item)
    end

    realTimer.newTimer(0, function ()
        local e = {offset = offset, position = position, button = 1}
        if events.mousePress then
            events.mousePress(e, item)
        end
        if events.mouseClick then
            events.mouseClick(e, item)
        end
        if events.mouseRelease then
            events.mouseRelease(e, item)
        end
        if events.focusLoss then
            events.focusLoss(nil, item)
        end
    end)

    return true
end


return this