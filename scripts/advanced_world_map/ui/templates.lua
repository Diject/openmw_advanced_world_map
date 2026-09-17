local ui = require('openmw.ui')
local util = require('openmw.util')
local auxUi = require('openmw_aux.ui')

local config = require("scripts.advanced_world_map.config.config")

local whiteTexture = ui.texture{ path = "white" }

local borderTextures = {
    ui.texture{ path = "textures/menu_thin_border_left.dds" },
    ui.texture{ path = "textures/menu_thin_border_right.dds" },
    ui.texture{ path = "textures/menu_thin_border_top.dds" },
    ui.texture{ path = "textures/menu_thin_border_bottom.dds" },
    ui.texture{ path = "textures/menu_thin_border_top_left_corner.dds" },
    ui.texture{ path = "textures/menu_thin_border_top_right_corner.dds" },
    ui.texture{ path = "textures/menu_thin_border_bottom_left_corner.dds" },
    ui.texture{ path = "textures/menu_thin_border_bottom_right_corner.dds" },
    ui.texture{ path = "textures/menu_thick_border_left.dds" },
    ui.texture{ path = "textures/menu_thick_border_right.dds" },
    ui.texture{ path = "textures/menu_thick_border_top.dds" },
    ui.texture{ path = "textures/menu_thick_border_bottom.dds" },
    ui.texture{ path = "textures/menu_thick_border_top_left_corner.dds" },
    ui.texture{ path = "textures/menu_thick_border_top_right_corner.dds" },
    ui.texture{ path = "textures/menu_thick_border_bottom_left_corner.dds" },
    ui.texture{ path = "textures/menu_thick_border_bottom_right_corner.dds" }
}

local this = {}

this.box = {
    type = ui.TYPE.Widget,
    content = ui.content{
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[1],
                tileH = false,
                tileV = true,
                size = util.vector2(2, 0),
                relativeSize = util.vector2(0, 1),
                position = util.vector2(0, 2),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[2],
                tileH = false,
                tileV = true,
                size = util.vector2(2, 0),
                relativeSize = util.vector2(0, 1),
                position = util.vector2(2, 2),
                relativePosition = util.vector2(1, 0),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[3],
                tileH = true,
                tileV = false,
                size = util.vector2(0, 2),
                relativeSize = util.vector2(1, 0),
                position = util.vector2(2, 0),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[4],
                tileH = true,
                tileV = false,
                size = util.vector2(0, 2),
                relativeSize = util.vector2(1, 0),
                position = util.vector2(2, 2),
                relativePosition = util.vector2(0, 1),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[5],
                size = util.vector2(2, 2),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[6],
                size = util.vector2(2, 2),
                position = util.vector2(2, 0),
                relativePosition = util.vector2(1, 0),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[7],
                size = util.vector2(2, 2),
                position = util.vector2(0, 2),
                relativePosition = util.vector2(0, 1),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[8],
                size = util.vector2(2, 2),
                position = util.vector2(2, 2),
                relativePosition = util.vector2(1, 1),
            },
        },
        {
            external = { slot = true },
            props = {
                position = util.vector2(2, 2),
                relativeSize = util.vector2(1, 1),
            }
        }
    },
}

this.boxSolid = auxUi.deepLayoutCopy(this.box)
this.boxSolid.type = ui.TYPE.Container
this.boxSolid.content:insert(1, {
    type = ui.TYPE.Image,
    props = {
        resource = whiteTexture,
        color = config.data.ui.backgroundColor,
        relativeSize = util.vector2(1, 1),
        size = util.vector2(4, 4)
    },
})

this.boxSolidThick = {
    type = ui.TYPE.Container,
    content = ui.content{
        {
            type = ui.TYPE.Image,
            props = {
                resource = whiteTexture,
                color = config.data.ui.backgroundColor,
                relativeSize = util.vector2(1, 1),
                size = util.vector2(8, 8)
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[9],
                tileH = false,
                tileV = true,
                size = util.vector2(4, 0),
                relativeSize = util.vector2(0, 1),
                position = util.vector2(0, 4),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[10],
                tileH = false,
                tileV = true,
                size = util.vector2(4, 0),
                relativeSize = util.vector2(0, 1),
                position = util.vector2(4, 4),
                relativePosition = util.vector2(1, 0),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[11],
                tileH = true,
                tileV = false,
                size = util.vector2(0, 4),
                relativeSize = util.vector2(1, 0),
                position = util.vector2(4, 0),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[12],
                tileH = true,
                tileV = false,
                size = util.vector2(0, 4),
                relativeSize = util.vector2(1, 0),
                position = util.vector2(4, 4),
                relativePosition = util.vector2(0, 1),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[13],
                size = util.vector2(4, 4),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[14],
                size = util.vector2(4, 4),
                position = util.vector2(4, 0),
                relativePosition = util.vector2(1, 0),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[15],
                size = util.vector2(4, 4),
                position = util.vector2(0, 4),
                relativePosition = util.vector2(0, 1),
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = borderTextures[16],
                size = util.vector2(4, 4),
                position = util.vector2(4, 4),
                relativePosition = util.vector2(1, 1),
            },
        },
        {
            external = { slot = true },
            props = {
                position = util.vector2(4, 4),
                relativeSize = util.vector2(1, 1),
            }
        }
    },
}


this.activeSelection = {
    type = ui.TYPE.Container,
    content = ui.content{
        {
            type = ui.TYPE.Image,
            props = {
                resource = whiteTexture,
                tileH = false,
                tileV = true,
                color = config.data.ui.defaultColor,
                relativeSize = util.vector2(0, 1),
                size = util.vector2(8, 0),
                alpha = 0.5,
            },
        },
        {
            external = { slot = true },
            props = {
                position = util.vector2(20, 0),
                relativeSize = util.vector2(1, 1),
                size = util.vector2(20, 0),
            }
        }
    },
}


this.inactiveSelection = {
    type = ui.TYPE.Container,
    content = ui.content{
        {
            external = { slot = true },
            props = {
                position = util.vector2(20, 0),
                relativeSize = util.vector2(1, 1),
                size = util.vector2(20, 0),
            }
        }
    },
}


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