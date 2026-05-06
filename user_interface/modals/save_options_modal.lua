local GenericActionsModal = require("user_interface.modals.generic_actions_modal")

local Dialog = {}
Dialog.__index = Dialog

function Dialog.new()
  local modal = GenericActionsModal.new()
  modal.cols = 2
  modal.optionColspan = 2
  modal.optionTextFormatter = function(_, option)
    local t = option and option.text or ""
    t = tostring(t)
    -- Call sites often pass "(1) Label"; strip leading "(n) " for clean buttons (keyboard shortcuts stay separate).
    return (t:gsub("^%(%d+%)%s*", ""))
  end
  local originalShow = modal.show
  function modal:show(title, options)
    return originalShow(self, title or "Save Options", options)
  end
  return modal
end

return Dialog
