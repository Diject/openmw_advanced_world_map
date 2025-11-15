local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local templates = require('openmw.interfaces').MWUI.templates

local commonData = require("scripts.advanced_world_map.common")
local configData = require("scripts.advanced_world_map.config.config")

local interval = require("scripts.advanced_world_map.ui.interval")
local tooltip = require("scripts.advanced_world_map.ui.tooltip")


---@class advancedWorldMap.ui.checkBox.params
---@field text string?
---@field checked boolean?
---@field textSize integer?
---@field visible boolean?
---@field position any? util.vector2
---@field relativePosition any? util.vector2
---@field anchor any? util.vector2
---@field tooltipContent any?
---@field event fun(checked : boolean, layout : any)?
---@field updateFunc fun()


---@param params advancedWorldMap.ui.checkBox.params
return function(params)
    local boxSize = util.vector2((params.textSize or 18) - 2, (params.textSize or 18) - 2)
    local texture = ui.texture { path = "white" }

    local visible
    if params.visible ~= nil then
        visible = params.visible
    else
        visible = true
    end

    local contentData = {
        type = ui.TYPE.Flex,
        props = {
            autoSize = true,
            position = params.position,
            relativePosition = params.relativePosition,
            anchor = params.anchor,
            horizontal = true,
            propagateEvents = false,
            visible = visible,
            arrange = ui.ALIGNMENT.Center,
        },
        userData = {
            checked = params.checked or false
        },
        events = {
            mouseRelease = async:callback(function(e, layout)
                if e.button ~= 1 then return end

                layout.userData.checked = not layout.userData.checked

                if layout.userData.checked then
                    layout.content[1].content[1].props.alpha = 1
                else
                    layout.content[1].content[1].props.alpha = 0
                end

                if params.event then
                    params.event(layout.userData.checked, layout)
                end

                params.updateFunc()
            end),

            focusLoss = async:callback(function(e, layout)
                tooltip.destroy(layout)
            end),

            mouseMove = async:callback(function(e, layout)
                if not params.tooltipContent then return end
                tooltip.createOrMove(e, layout, params.tooltipContent)
            end),
        },
        content = ui.content {
            {
                template = templates.boxThick,
                type = ui.TYPE.Container,
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        props = {
                            resource = texture,
                            size = boxSize,
                            anchor = util.vector2(0, 0.5),
                            inheritAlpha = false,
                            alpha = params.checked and 1 or 0,
                            color = configData.data.ui.defaultColor,
                        },
                    }
                },
            },
            interval(4, 4),
            {
                template = templates.textNormal,
                type = ui.TYPE.Text,
                props = {
                    text = params.text or "Enable",
                    textColor = configData.data.ui.defaultColor,
                    textSize = params.textSize or 18,
                    anchor = util.vector2(0, 0.5),
                    multiline = false,
                    wordWrap = false,
                    textAlignH = ui.ALIGNMENT.Start,
                },
            }
        }
    }

    return contentData
end