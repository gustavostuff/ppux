-- window_behaviors.lua
-- Aggregates behavioral mixins for Window.

local installCore = require("user_interface.windows_system.window_behaviors_core")
local installLayout = require("user_interface.windows_system.window_behaviors_layout")
local installMouse = require("user_interface.windows_system.window_behaviors_mouse")

return function(Window)
  installCore(Window)
  installLayout(Window)
  installMouse(Window)
end
