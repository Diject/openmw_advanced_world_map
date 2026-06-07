local ui = require("openmw.ui")
local util = require("openmw.util")
local async = require("openmw.async")

local config = require("scripts.advanced_world_map.config.config")

local tableLib = require("scripts.advanced_world_map.utils.table")
local uiUtils = require("scripts.advanced_world_map.ui.utils")


local separatorTexture = ui.texture{ path = "textures/menu_thin_border_right.dds" }


---@class advancedWorldMap.ui.horizontalSelector
local selectorMeta = {}
selectorMeta.__index = selectorMeta


function selectorMeta:resetSelection()
    for _, btn in pairs(self.buttons) do
        btn.content[1].props.visible = false
    end
end


---@param index integer
function selectorMeta:select(index)
    local btn = self.buttons[index]
    if not btn then return end

    self:resetSelection()
    btn.content[1].props.visible = true
    if btn.userData.callback then
        btn.userData.callback(btn)
    end
    self.update()
end


---@class advancedWorldMap.ui.horizontalSelector.buttonParams
---@field text string
---@field onClick fun(layout: Layout)
---@field checked boolean?


---@class advancedWorldMap.ui.horizontalSelector.params
---@field size Vector2
---@field fontSize number?
---@field anchor Vector2?
---@field position Vector2?
---@field buttons advancedWorldMap.ui.horizontalSelector.buttonParams[]
---@field update function


---@param params advancedWorldMap.ui.horizontalSelector.params
return function(params)
    params.fontSize = params.fontSize or config.data.ui.fontSize

    ---@class advancedWorldMap.ui.horizontalSelector
    local meta = setmetatable({}, selectorMeta)

    meta.params = params
    meta.btnCount = #params.buttons
    meta.separatorWidth = 1
    meta.update = params.update

    meta.btnSize = util.vector2((params.size.x - meta.separatorWidth * (meta.btnCount - 1)) / meta.btnCount, params.size.y)

    meta.layout = {
        type = ui.TYPE.Flex,
        props = {
            size = params.size,
            anchor = params.anchor,
            position = params.position,
            horizontal = true,
            align = ui.ALIGNMENT.Center,
            arrange = ui.ALIGNMENT.Center,
        },
        external = {
            grow = 1,
        },
        userData = {
            meta = meta,
        },
        content = ui.content{}
    }

    meta.buttons = {}


    ---@param btnParams advancedWorldMap.ui.horizontalSelector.buttonParams
    local function addBtn(btnParams)

        if #meta.layout.content > 0 then
            meta.layout.content:add{
                type = ui.TYPE.Image,
                props = {
                    resource = separatorTexture,
                    tileH = false,
                    tileV = true,
                    size = util.vector2(meta.separatorWidth, 0),
                    relativeSize = util.vector2(0, meta.separatorWidth),
                },
            }
        end

        local btnLayout
        local btnIndex = #meta.buttons + 1

        btnLayout = {
            type = ui.TYPE.Widget,
            props = {
                anchor = util.vector2(0.5, 0.5),
                size = meta.btnSize,
            },
            external = {
                grow = 1,
            },
            userData = {
                callback = btnParams.onClick,
            },
            events = {
                mouseClick = async:callback(function()
                    meta:select(btnIndex)
                end)
            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        relativeSize = util.vector2(1, 1),
                        color = config.data.ui.defaultColor,
                        resource = uiUtils.whiteTexture,
                        alpha = 0.25,
                        visible = btnParams.checked or false,
                    },
                },
                {
                    type = ui.TYPE.Text,
                    props = {
                        text = btnParams.text,
                        textSize = params.fontSize,
                        textColor = config.data.ui.defaultColor,
                        textAlignH = ui.ALIGNMENT.Center,
                        textAlignV = ui.ALIGNMENT.Center,
                        autoSize = false,
                        size = meta.btnSize
                    },
                },
            }
        }

        meta.layout.content:add(btnLayout)
        table.insert(meta.buttons, btnLayout)
    end

    for _, btnParams in ipairs(params.buttons) do
        addBtn(btnParams)
    end

    return meta.layout
end