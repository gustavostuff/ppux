local Shared = require("controllers.app.core_controller_shared")

return function(AppCoreController)

function AppCoreController:showRenameWindowModal(win)
  if not (self.renameWindowModal and win and type(win) == "table") then
    return false
  end
  if win.titleLocked == true then
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

function AppCoreController:showRelocationPointerCalculatorModal()
  if not self.relocationPointerCalculatorModal then
    return false
  end
  self.relocationPointerCalculatorModal:show({
    statusCallback = function(message)
      if self.setStatus then
        self:setStatus(message)
      end
    end,
  })
  return true
end

function AppCoreController:showNametableBreakpointCalculatorModal()
  if not self.nametableBreakpointCalculatorModal then
    return false
  end
  self.nametableBreakpointCalculatorModal:show({
    statusCallback = function(message)
      if self.setStatus then
        self:setStatus(message)
      end
    end,
  })
  return true
end

function AppCoreController:showGalleryRomResultModal(ok, message)
  if not self.galleryRomResultModal then
    return false
  end
  self.galleryRomResultModal:show({
    ok = ok == true,
    message = tostring(message or (ok and "Done." or "Failed.")),
  })
  return true
end

--- App-toolbar entry: confirm packed sketches, then build gallery ROM.
function AppCoreController:showGalleryRomConfirmModal()
  local SketchCanvasGalleryRomController = require("controllers.game_art.sketch_canvas_gallery_rom_controller")
  local sketches = SketchCanvasGalleryRomController.collectPackedSketches(self.wm)
  if #sketches < 1 then
    return self:showGalleryRomResultModal(
      false,
      "No packed sketch canvases. Open a Sketch canvas, paint, and press Generate first."
    )
  end
  if not self.galleryRomConfirmModal then
    return false
  end
  self.galleryRomConfirmModal:show({
    sketches = sketches,
    onConfirm = function(selected)
      local ok, pathOrErr = SketchCanvasGalleryRomController.buildGalleryRom(self, selected)
      if ok then
        self:showGalleryRomResultModal(true, "Wrote gallery ROM:\n" .. tostring(pathOrErr))
        if self.setStatus then
          self:setStatus("Gallery ROM: " .. tostring(pathOrErr))
        end
      else
        self:showGalleryRomResultModal(false, tostring(pathOrErr or "Gallery ROM build failed"))
        if self.setStatus then
          self:setStatus("Gallery ROM failed: " .. tostring(pathOrErr or "error"))
        end
      end
    end,
  })
  return true
end

end
