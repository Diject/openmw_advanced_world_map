local ui = require('openmw.ui')
local util = require('openmw.util')

local uiUtils = require("scripts.advanced_world_map.ui.utils")

return function (x, y)
    return {
        type = ui.TYPE.Widget,
        props = uiUtils.props{
            size = util.vector2(x or 2, y or 2),
        },
    }
end