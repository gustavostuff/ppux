-- window_behaviors.lua
-- Aggregates behavioral mixins for Window.

local installCore = require("ui.windows_system.window_behaviors_core")
local installLayout = require("ui.windows_system.window_behaviors_layout")
local installMouse = require("ui.windows_system.window_behaviors_mouse")

return function(Window)
  installCore(Window)
  installLayout(Window)
  installMouse(Window)
end
