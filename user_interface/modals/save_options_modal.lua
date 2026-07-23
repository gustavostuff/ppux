local GenericActionsModal = require("user_interface.modals.generic_actions_modal")

local Dialog = {}
Dialog.__index = Dialog

function Dialog.new()
  local modal = GenericActionsModal.new()
  modal.cols = 2
  modal.optionColspan = 2
  local originalShow = modal.show
  function modal:show(title, options)
    return originalShow(self, title or "Save Options", options)
  end
  return modal
end

return Dialog
