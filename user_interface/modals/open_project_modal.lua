-- Thin wrapper: backward-compatible project / ROM file picker (.lua, .ppux, .nes).
-- Full implementation: user_interface/modals/open_file_modal.lua
local OpenFileModal = require("user_interface.modals.open_file_modal")

local M = {}
function M.new()
  return OpenFileModal.new(OpenFileModal.presets.project)
end

return M
