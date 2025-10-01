local util = require('openmw.util')

local this = {}


this.l10nKey = "advanced_world_map"

this.settingPage = "AdvancedWorldMap:Settings"

this.configMainSectionName = "Settings:AdvWMap:Main"

this.menuKeyId = "AdvWMap:menuKey"

this.localDataName = "AdvancedWorldMap:playerData"

this.mapMenuId = "__MAP__"

this.globalDataStorageName = "AdvancedWorldMap:globalDataStorage"

this.lastZoomFieldId = "lastZoomValue"

this.discoveredLocsFieldId = "discoveredLocationsHashSet"

this.rightClickMenuId = "__MAP:RIGHTCLICKMENU__"
this.mapWidgetHeaderLayoutId = "__MAP:WIDGETHEADERLAYOUT__"
this.mapWidgetWindowLayoutId = "__MAP:WIDGETWINDOWLAYOUT__"

this.defaultColorData = {202/255, 165/255, 96/255}
this.defaultColor = util.color.rgb(this.defaultColorData[1], this.defaultColorData[2], this.defaultColorData[3])

this.defaultLightColorData = {255/255, 255/255, 255/255}
this.defaultLightColor = util.color.rgb(this.defaultLightColorData[1], this.defaultLightColorData[2], this.defaultLightColorData[3])

this.selectedColorData = {0.2, 1, 0.2}
this.selectedColor = util.color.rgb(this.selectedColorData[1], this.selectedColorData[2], this.selectedColorData[3])

this.linkColorData = {112 / 255, 126 / 255, 207 / 255}
this.linkColor = util.color.rgb(this.linkColorData[1], this.linkColorData[2], this.linkColorData[3])

this.disabledColorData = {0.5, 0.5, 0.5}
this.disabledColor = util.color.rgb(this.disabledColorData[1], this.disabledColorData[2], this.disabledColorData[3])

this.textShadowColorData = {0.1, 0.1, 0.1}
this.textShadowColor = util.color.rgb(this.textShadowColorData[1], this.textShadowColorData[2], this.textShadowColorData[3])

this.backgroundColorData = {0, 0, 0}
this.backgroundColor = util.color.rgb(this.backgroundColorData[1], this.backgroundColorData[2], this.backgroundColorData[3])

this.mapWaterColor = util.color.rgb(36 / 255, 53 / 255, 48 / 255)

this.whiteTexture = nil
pcall(function ()
    local constants = require('scripts.omw.mwui.constants')
    this.whiteTexture = constants.whiteTexture
end)

this.mapMarkerPath = "textures/icons/advanced_world_map/squareMarker.dds"
this.playerMapMarkerPath = "textures/icons/advanced_world_map/playerMapMarker.dds"
this.playerMarkerDir = "textures/icons/advanced_world_map/playerMarker/"

this.searchWidgetIcon = "textures/icons/advanced_world_map/widget/searchIco.dds"


this.customMapDir = "textures/advanced_world_map/map/"
this.defaultTRMapDir = "textures/advanced_world_map/TRmap/"
this.defaultBaseMapDir = "textures/advanced_world_map/basemap/"
this.questDataMapDir = "questData/"

this.exteriorCellIdFormat = "Esm3ExteriorCell:%d:%d"
this.localMapTexturesDir = "textures/advanced_world_map/localMap/"

this.dataInitializerTypes = {
    "Auto",
    "Your custom",
    "Quest Guider's Quest Data",
    "Tamriel Rebuilt++",
    "Base game",
}


function this.colorToArray(color)
    return {color.r, color.g, color.b, color.a}
end

function this.copyVector3(vector)
    return util.vector3(vector.x, vector.y, vector.z)
end

function this.distance2D(vector1, vector2)
    return math.sqrt((vector1.x - vector2.x)^2 + (vector1.y - vector2.y)^2)
end

return this