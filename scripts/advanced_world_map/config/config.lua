local util = require('openmw.util')

local commonData = require("scripts.advanced_world_map.common")
local tableLib = require("scripts.advanced_world_map.utils.table")


local this = {}

---@class questGuider.config
this.default = {
    version = 1,
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
        centerOnPlayer = true,
        discoveryRadius = 1500,
        updateFrequency = 10,
    },
    legend = {
        markerSize = 6,
        onlyDiscovered = false,
        alpha = {
            region = 12,
            entrance = 80,
            city = 40,
        },
        visibility = {
            regions = true,
            cities = true,
            playerMarker = true,
            labels = true,
            markers = true,
        }
    },
    tileset = {
        onlyDiscovered = false,
        zoomToShow = 6,
    },
    fastTravel = {
        enabled = true,
        onlyDiscovered = false,
        allowToInterior = true,
        baseMagickaCost = 60,
        additionalCost = 2,
    },
    data = {
        initializer = commonData.dataInitializerTypes[1],
    },
    ui = {
        fontSize = 18,
        defaultColor = commonData.defaultColor,
        defaultLightColor = commonData.defaultLightColor,
        defaultDarkColor = commonData.defaultDarkColor,
        whiteColor = commonData.whiteColor,
        backgroundColor = commonData.backgroundColor,
        -- disabledColor = commonData.disabledColor,
        foundMarkerColor = commonData.foundMarkerColor,
        foundMarkerLightColor = commonData.foundMarkerLightColor,
        textShadowColor = commonData.textShadowColor,
        defaultTextureColor = commonData.defaultTextureColor,
        mouseScrollAmount = 36,
        headerBackgroundAlpha = 100,
        scrollArrowSize = 16,
        resizerSize = 16,
        textHeightMul = 0.7,
    },
}


---@class questGuider.config
this.data = tableLib.deepcopy(this.default)

return this