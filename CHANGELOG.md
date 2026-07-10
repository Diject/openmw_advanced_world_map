Version 1.13.3

- Fixed markers getting stuck after zooming out.
- Made zooming faster.
- Fixed various layout issues.

Version 1.13.2

- Fixed gaps between world map tiles.
- Fixed some cases of overlapping markers on the local map.

Version 1.13.1

- Fixed fast travel time calculation.
- Added support for 'textures' field in world map info (AdvancedWorldMap.MapImageInfo type).

Version 1.13.0

- Added support for overlay textures on the world map.

Version 1.12.0

- At lower zoom levels, local map markers are now replaced with a single location name.
- Reduced the active rendered map area (improving performance for the minimap mode at high zoom levels, but markers now update as needed rather than only when loading a new cell).
- Added the ability to pay for fast travel using gold and health.
- The player marker now renders above all other layers in pinned mode.
- Fixed a gradual performance regression on the world map.
- Fixed a bug causing the zoom level to increase during cell transitions or loading.

Version 1.11.0

- Added Morrowind-style header.
- Added background for local markers.
- Reworked marker grouping and sizes.
- Added item and NPC search support (requires OpenMW 0.52(dev ver)).
- Added previews for the initialization menu.
- Added the ability to resize the window by its edges.
- Fixed incorrect zoom threshold for Gridmap.
- Improved mouse scroll registration.
- API: Added new parameters to OnSearchEvent, MapWidget:createTextMarker.

Version 1.10.7

- The travel routes message now only appears once.

Version 1.10.6

- Added a workaround for an issue where OpenMW provided incorrect door data.

Version 1.10.5

- Fixed incorrect transport data generation.

Version 1.10.4

- Fixes and improvements to transport data generation.
- Increased priority of the player marker on the map.

Version 1.10.3

- Fixed an issue with text shadow color after a search.

Version 1.10.2

- Fixed tooltips getting stuck.

Version 1.10.1

- Fixed descriptions of the new settings.
- Changed default values for some settings.
- Added a setting for the player marker size.
- Changed the map layer order.

Version 1.10.0

- Added the ability to display travel routes.
- Added a couple of hotkeys for gamepads.

Version 1.9.1

- Added border thickness settings.
- Added an additional text shadow color setting.

Version 1.9.0

- Added a map texture for the whole of Tamriel (the gridmap) via a separate .omwscript file.
- Fixed search interaction with marker visibility.
- Fixed saving of disabled door state.

Version 1.8.0

- Added support for the TotSP mod.
- Marker colors for the local and world maps can now be configured independently.
- Some mod API methods are now available in the global scope.
- API: New events - onConfigChanged, onWorldMapTextureInit, onWorldMapLocalTextureGet, onWorldMapTextureGet.

Version 1.7.0

- Changed the initialization of the map data.

Version 1.6.2

- Fixed buttons for some users.

Version 1.6.1

- Improved minimap mode behavior.

Version 1.6.0

- Added hotkeys for previous-next map (default: mouse buttons 4 and 5).
- Added minimap mode, where in non-interactive mode the map will have separate size and position from the main ones. (Access from the Legend widget, does not replace the standard minimap!)
- API: New events - onLegendWidgetCreate, onDiscover.
- API: New methods - Interface: getExteriorCellName, getEntranceMarkerData; MapWidget: getZoomModeThreshold / eScale, onZoomMarkersRect.

Version 1.5.4

- Added workaround for a bug in the dev version of OpenMW.

Version 1.5.3

- Added a setting for the context menu hotkey.

Version 1.5.2

- Fixed incorrect region names.

Version 1.5.1

- Added a setting to reset the menu position.

Version 1.5.0

- Marker text is now grouped at greater zoom distances for better readability.
- Local map textures now load gradually to improve menu responsiveness.
- Many improvements to Notes.
- Locations with journal info are always shown on the world map.
- Added compatibility with mods that set chargenState below -1.
- API: New events — onMapDestroyed, onMapElementCreate, onWidgetOpened, onWidgetClosed.
- API: New methods — Interface: openMapMenu, getMapMenu, closeMapMenu, setConfigValue, getCellNameById; Map: iterateCachedMapWidgets; MapWidget: get/setPosition.
- API: Added isValid method for mapWidget and map elements.

Version 1.4.0

- Added outlining of areas above water level for the mod's built-in world map textures, to give them a slightly paper map-like appearance.
- Added last visit date to location door marker tooltips.
- New API events: onUpdate, onZoomMarkersUpdated.

Version 1.3.0

- Updated images of the default maps provided by the mod.
- Added support for a new map texture type.

Version 1.2.1

- Fixed data generation issue.

Version 1.2.0

- Added the ability to pin the menu.
- Improved gamepad controls.
- Improved hotkey behavior.
- Added the ability to bind toggling between world/local map and pinning the menu.
- New API events: onGroundTexturesPlace, onCellMarkersCreate, onWorldMapTextureInitialize.
- New API functions: hasActiveWidget, isInFocus, setPlayerMarkerVisibility, getPlayerMarkerVisibility, updateWorldMapTexture.

Version 1.1.2

- Fixed fast travel cooldown.

Version 1.1.1

- Fixed zooming over a marker.
- Fixed opening the mod in the controller menu.

Version 1.1.0

- Changed data initialization and added a message when opening the map if initialization did not complete correctly.
- Added a setting to replace the standard map menu with this one.
- Added partial cache clearing when closing the map.
- API: Added the "onMapElementInitialized" event.

Version 1.0.1

- The controller's B button now exits the menu.
- The last shown position is now saved when player following is disabled.
- Added a setting to exit the menu immediately instead of switching to a non-interactive mode.
- Fixed bugs in the API.

