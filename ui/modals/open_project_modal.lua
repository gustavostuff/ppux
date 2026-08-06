-- Thin wrapper: backward-compatible project / ROM file picker (.lua, .ppux, .nes).
-- Full implementation: ui/modals/open_file_modal.lua
local OpenFileModal = require("ui.modals.open_file_modal")

local M = {}
function M.new()
  return OpenFileModal.new(OpenFileModal.presets.project)
end

return M
