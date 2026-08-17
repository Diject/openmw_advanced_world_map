local ui = require('openmw.ui')
local util = require('openmw.util')
local auxUi = require('openmw_aux.ui')
local templates = require('openmw.interfaces').MWUI.templates

local config = require("scripts.advanced_world_map.config.config")

local this = {}

this.boxSolidThick = auxUi.deepLayoutCopy(templates.boxSolidThick)
this.boxSolid = auxUi.deepLayoutCopy(templates.boxSolid)
this.box = auxUi.deepLayoutCopy(templates.box)

pcall(function ()
    this.boxSolidThick.content[1].template.props.color = config.data.ui.backgroundColor
    this.boxSolid.content[1].template.props.color = config.data.ui.backgroundColor
    this.box.type = ui.TYPE.Widget
end)


this.roundedBackground = {
    type = ui.TYPE.Container,
    content = ui.content{
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                autoSize = false,
                relativeSize = util.vector2(1, 1),
            },
            content = ui.content {
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture{ path = "textures/icons/advanced_world_map/rWhiteRect_left.png" },
                        color = config.data.ui.backgroundColor,
                        alpha = 0.5,
                        size = util.vector2(4, 0),
                        relativeSize = util.vector2(0, 1)
                    },
                },
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture{ path = "textures/icons/advanced_world_map/rWhiteRect_center.png" },
                        color = config.data.ui.backgroundColor,
                        alpha = 0.5,
                        size = util.vector2(-8, 0),
                        relativeSize = util.vector2(1, 1)
                    },
                },
                {
                    type = ui.TYPE.Image,
                    props = {
                        resource = ui.texture{ path = "textures/icons/advanced_world_map/rWhiteRect_right.png" },
                        color = config.data.ui.backgroundColor,
                        alpha = 0.5,
                        size = util.vector2(4, 0),
                        relativeSize = util.vector2(0, 1)
                    },
                }
            }
        },
    }
}


return this