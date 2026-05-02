local Shared = require("controllers.app.core_controller_shared")

return function(AppCoreController)

function AppCoreController:showRenameWindowModal(win)
  if not (self.renameWindowModal and win and type(win) == "table") then
    return false
  end

  self.renameWindowModal:show({
    window = win,
    initialTitle = win.title or "",
    onConfirm = function(newTitle, targetWindow)
      if not targetWindow then return end
      local beforeTitle = targetWindow.title or ""
      targetWindow.title = newTitle
      if beforeTitle ~= newTitle and self.undoRedo and self.undoRedo.addWindowRenameEvent then
        self.undoRedo:addWindowRenameEvent({
          type = "window_rename",
          win = targetWindow,
          beforeTitle = beforeTitle,
          afterTitle = newTitle,
        })
      end
    end,
  })

  return true
end

function AppCoreController:showRomPaletteAddressModal(win, col, row)
  if not (self.romPaletteAddressModal and win and type(win) == "table") then
    return false
  end

  local rowColors = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[(row or 0) + 1] or nil
  local existingAddr = rowColors and rowColors[(col or 0) + 1] or nil
  local initialAddress = type(existingAddr) == "number" and string.format("0x%06X", existingAddr) or ""

  self.romPaletteAddressModal:show({
    title = "Enter color address",
    window = win,
    col = col,
    row = row,
    initialAddress = initialAddress,
    onConfirm = function(addressText, targetWindow, targetCol, targetRow)
      local beforeState = Shared.captureRomPaletteAddressUndoState(targetWindow)
      local addr, parseErr = Shared.parseHexAddress(addressText)
      if not addr then
        self:setStatus(parseErr)
        self:showToast("error", parseErr)
        return false
      end

      local ok, err = targetWindow:setCellAddress(targetCol, targetRow, addr)
      if not ok then
        local message = err or "Failed to assign ROM palette address"
        self:setStatus(message)
        self:showToast("error", message)
        return false
      end
      if self.invalidatePpuFrameLayersAffectedByPaletteWin then
        self:invalidatePpuFrameLayersAffectedByPaletteWin(targetWindow)
      end
      if self.undoRedo and self.undoRedo.addRomPaletteAddressEvent then
        self.undoRedo:addRomPaletteAddressEvent({
          type = "rom_palette_address",
          win = targetWindow,
          beforeState = beforeState,
          afterState = Shared.captureRomPaletteAddressUndoState(targetWindow),
        })
      end
      return true
    end,
  })

  return true
end

end
