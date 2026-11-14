local ui = require("openmw.ui")
local util = require("openmw.util")
local async = require("openmw.async")
local core = require("openmw.core")
local I = require("openmw.interfaces")

local config = require("scripts.advanced_world_map.config.config")
local commonData = require("scripts.advanced_world_map.common")
local uiUtils = require("scripts.advanced_world_map.ui.utils")
local menuMode = require("scripts.advanced_world_map.ui.menuMode")
local menuHandler = require("scripts.advanced_world_map.menuHandler")
local templates = require("scripts.advanced_world_map.ui.templates")
local realTimer = require("scripts.advanced_world_map.realTimer")
local hotkeyLayers = require("scripts.advanced_world_map.input.hotkeyLayers")
local keysModule = require("scripts.advanced_world_map.input.keys")

local checkBox = require("scripts.advanced_world_map.ui.checkBox")

local this = {}

this.menu = nil
this.inFocus = nil
this.closeTimestamp = 0
this.selectedItemIndex = 0
this.timer = nil

---@class questGuider.ui.contextMenu.create.params.element
---@field type integer? -- 0: separator, 1: text, 2: button, 3: checkbox
---@field text string?
---@field data any?
---@field fontSize number?
---@field callback fun(data: any, layout: any)?

---@class questGuider.ui.contextMenu.create.params
---@field position any
---@field fontSize number
---@field elements questGuider.ui.contextMenu.create.params.element[]


local template = {
    type = ui.TYPE.Container,
    content = ui.content{
        {
            external = uiUtils.external{ slot = true },
            props = uiUtils.props{
                relativeSize = util.vector2(1, 1),
                size = util.vector2(4, 4),
            },
            content = ui.content{
                {
                    type = ui.TYPE.Image,
                    props = uiUtils.props{
                        resource = uiUtils.whiteTexture,
                        color = config.data.ui.defaultColor,
                        relativeSize = util.vector2(1, 1),
                        alpha = 0,
                    }
                },
            }
        },
    },
}

local selectedTemplate = {
    type = ui.TYPE.Container,
    content = ui.content{
        {
            external = uiUtils.external{ slot = true },
            props = uiUtils.props{
                relativeSize = util.vector2(1, 1),
                size = util.vector2(4, 4),
            },
            content = ui.content{
                {
                    type = ui.TYPE.Image,
                    props = uiUtils.props{
                        resource = uiUtils.whiteTexture,
                        color = config.data.ui.defaultColor,
                        relativeSize = util.vector2(1, 1),
                        alpha = 0.2,
                    }
                },
            }
        },
    },
}


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
    I.DijectKeyBindings.action.register(commonData.bottomMarkerKeyId, directionHotkeyFuncs[2])
    I.DijectKeyBindings.keybind.register("C_A", this.clickOnSelectedItem)
end

local function unregisterHotkeys()
    I.DijectKeyBindings.action.unregister(commonData.topMarkerKeyId, directionHotkeyFuncs[1])
    I.DijectKeyBindings.action.unregister(commonData.bottomMarkerKeyId, directionHotkeyFuncs[2])
    I.DijectKeyBindings.keybind.unregister("C_A", this.clickOnSelectedItem)
end


---@param params questGuider.ui.contextMenu.create.params
---@return number
function this.create(params)
    this.destroy()

    local id = core.getRealTime()

    local screenSize = uiUtils.getScaledScreenSize()
    local anchor = (screenSize.x - params.position.x) < screenSize.x * 0.75 and util.vector2(1, 0) or nil

    local layout = {
        layer = commonData.messageLayer,
        template = templates.boxSolid,
        props = uiUtils.props{
            alpha = 1,
            anchor = anchor,
        },
        userData = {
            id = id,
        },
        events = {
            mouseMove = async:callback(function(coord, layout)
                this.inFocus = true
            end),

            focusLoss = async:callback(function(e, layout)
                this.inFocus = false
            end),
        },
        content = ui.content{
            {
                type = ui.TYPE.Flex,
                props = uiUtils.props{
                    horizontal = false,
                    align = ui.ALIGNMENT.Center,
                    arrange = ui.ALIGNMENT.Center,
                },
                content = ui.content{}
            }
        }
    }


    local containerLayout = {
        type = ui.TYPE.Container,
        content = ui.content{
            {
                external = uiUtils.external{ slot = true },
                props = uiUtils.props{
                    relativeSize = util.vector2(1, 1),
                    size = util.vector2(4, 4),
                },
            }
        },
    }

    local height = 4

    local function processElementData(data)
        if data.type == 0 then
            layout.content[1].content:add{
                type = ui.TYPE.Image,
                props = uiUtils.props{
                    resource = ui.texture{ path = "textures/menu_thin_border_top.dds" },
                    tileH = true,
                    tileV = false,
                    anchor = util.vector2(0.5, 0.5),
                    size = util.vector2(50, 2),
                },
            }
            return
        end

        local element
        element = {
            template = template,
            props = uiUtils.props{},
            userData = {},
            events = {
                mouseMove = async:callback(function(coord, layout)
                    if not this.menu then return end
                    element.template = selectedTemplate
                    this.inFocus = true
                    this.menu:update()
                end),

                focusLoss = async:callback(function(e, layout)
                    if not this.menu then return end
                    element.template = template
                    this.inFocus = false
                    this.menu:update()
                end),
            },
            content = ui.content{}
        }

        if not data.type or data.type == 2 then
            element.content:add{
                type = ui.TYPE.Text,
                props = uiUtils.props{
                    text = data.text or "",
                    textSize = data.fontSize or params.fontSize or config.data.ui.fontSize,
                    textColor = config.data.ui.defaultColor,
                    position = util.vector2(4, 4)
                }
            }
            element.events.mousePress = async:callback(function(e, layout)
                if data.callback then
                    data.callback(nil, element)
                end
            end)
            element.userData.onClick = element.events.mousePress

        elseif data.type == 1 then
            element.content:add{
                type = ui.TYPE.Text,
                props = uiUtils.props{
                    text = data.text or "",
                    textSize = data.fontSize or params.fontSize or config.data.ui.fontSize,
                    textColor = config.data.ui.defaultColor,
                    position = util.vector2(4, 4)
                }
            }
            element.events = nil

        elseif data.type == 3 then
            local cb = checkBox{
                updateFunc = function ()
                    this.menu:update()
                end,
                checked = data.data,
                text = data.text or "",
                textSize = data.fontSize or params.fontSize or config.data.ui.fontSize,
                visible = true,
                inheritAlpha = true,
                position = util.vector2(4, 4),
                event = data.callback,
            }
            cb.events.focusLoss = element.events.focusLoss
            cb.events.mouseMove = element.events.mouseMove
            element.content:add(cb)
            element.userData.onClick = cb.events.mousePress
            element.userData.onClickLayout = cb
        end

        layout.content[1].content:add(element)
        height = height + 8
    end

    for _, data in ipairs(params.elements) do
        processElementData(data)
    end

    height = height + uiUtils.getContentHeight(layout.content[1].content)

    layout.props.position = (params.position.y + height > screenSize.y) and util.vector2(params.position.x, screenSize.y - height) or
        params.position

    this.inFocus = nil
    this.closeTimestamp = core.getRealTime() + 3

    local func
    func = function ()
        this.timer = realTimer.newTimer(0, function ()
            if not this.menu then return end

            local lastAlpha = layout.props.alpha

            if this.inFocus == nil then
                if core.getRealTime() > this.closeTimestamp then
                    this.destroy()
                    return
                end
            elseif this.inFocus == false then
                layout.props.alpha = math.max(0, layout.props.alpha - core.getRealFrameDuration() * 1.5)
            else
                layout.props.alpha = math.min(1, layout.props.alpha + core.getRealFrameDuration() * 3)
            end

            if layout.props.alpha <= 0 or not menuMode.isMenuInteractive() or not menuHandler.hasActiveMenus() then
                this.destroy()
                return
            end

            if lastAlpha ~= layout.props.alpha then
                this.menu:update()
            end

            func()
        end)
    end
    func()

    this.menu = ui.create(layout)

    this.selectedItemIndex = 0
    if keysModule.isGamepad and this.menu then
        this.selectItem(1)
    end

    hotkeyLayers.register{
        id = commonData.hotkeyLayerContextMenu,
        priority = 300,
        activateFun = registerHotkeys,
        deactivateFun = unregisterHotkeys,
    }

    return id
end


function this.destroy()
    hotkeyLayers.unregister(commonData.hotkeyLayerContextMenu)
    if not this.menu then return end

    pcall(function ()
        this.menu:destroy()
    end)
    this.menu = nil
    this.selectedItemIndex = 0

    if this.timer then
        this.timer()
        this.timer = nil
    end
end

function this.update()
    if this.menu and this.menu.layout then
        this.menu:update()
    end
end


local function resetSelection(content)
    for i, lay in ipairs(content) do
        if lay.template and lay.template == selectedTemplate then
            lay.template = template
        end
    end
end


---@param index integer?
function this.selectItem(index)
    if not this.menu or not this.menu.layout then return false end

    this.closeTimestamp = core.getRealTime() + 4

    local content = this.menu.layout.content[1].content
    local itemCount = #content

    resetSelection(content)

    if itemCount < 1 then return false end

    local p, ind
    for i = 1, 100 do
        p = p or index or (this.selectedItemIndex + 1)
        if p > itemCount then
            p = 1
        elseif p < 1 then
            p = itemCount
        end

        local lay = uiUtils.getFromContent(content, p)
        if lay and lay.userData and lay.userData.onClick then
            ind = p
            break
        end

        p = p + 1
    end

    if not ind then return false end

    content[ind].template = selectedTemplate
    this.selectedItemIndex = ind
    this.update()

    return true
end


function this.clickOnSelectedItem()
    if not this.menu or not this.menu.layout then return false end

    local content = this.menu.layout.content[1].content
    local item = uiUtils.getFromContent(content, this.selectedItemIndex)
    if not item or not item.userData or not item.userData.onClick then return false end

    item.userData.onClick(
        {offset = util.vector2(0, 0), position = util.vector2(0, 0), button = 1},
        item.userData.onClickLayout or item
    )

    return true
end


---@return number?
function this.getActiveMenuId()
    return this.menu and this.menu.layout and this.menu.layout.userData.id or nil
end


return this