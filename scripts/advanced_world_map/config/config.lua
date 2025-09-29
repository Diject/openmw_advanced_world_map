local util = require('openmw.util')

local commonData = require("scripts.advanced_world_map.common")
local tableLib = require("scripts.advanced_world_map.utils.table")


local this = {}

---@class questGuider.config
this.default = {
    main = {
        menuKey = "M",
        relativeSize = {
            x = 70,
            y = 70,
        },
        relativePosition = {
            x = 15,
            y = 15,
        },
    },
    legend = {
        onlyDiscovered = false,
    },
    tileset = {
        onlyDiscovered = false,
    },
    data = {
        initializer = commonData.dataInitializerTypes[1],
    },
    ui = {
        fontSize = 18,
        defaultColor = commonData.defaultColor,
        defaultLightColor = commonData.defaultLightColor,
        backgroundColor = commonData.backgroundColor,
        disabledColor = commonData.disabledColor,
        selectionColor = commonData.selectedColor,
        shadowColor = commonData.selectedShadowColor,
        linkColor = commonData.linkColor,
        mouseScrollAmount = 36,
        headerBackgroundAlpha = 100,
    },
}


---@class questGuider.config
this.data = tableLib.deepcopy(this.default)

return this