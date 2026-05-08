-- Thin wrapper: reference tracing PNG picker (.png only).
-- Full implementation: user_interface/modals/open_file_modal.lua
local OpenFileModal = require("user_interface.modals.open_file_modal")

local M = {}
function M.new()
  return OpenFileModal.new(OpenFileModal.presets.png)
end

return M
