-- Thin wrapper: choose a folder for saving a no-ROM project (.lua / .ppux).
-- Reuses open_file_modal directory browsing.
local OpenFileModal = require("user_interface.modals.open_file_modal")

local M = {}
function M.new()
  return OpenFileModal.new(OpenFileModal.presets.saveProjectFolder)
end

return M
