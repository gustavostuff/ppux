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

  col = math.floor(tonumber(col) or 0)
  row = math.floor(tonumber(row) or 0)
  local rowColors = win.paletteData and win.paletteData.romColors and win.paletteData.romColors[row + 1] or nil
  local existingAddr = rowColors and rowColors[col + 1] or nil
  local initialAddress = type(existingAddr) == "number" and string.format("0x%06X", existingAddr) or ""
  -- Empty cell: suggest left neighbor + 1 so sequential ROM color rows fill quickly.
  if initialAddress == "" and col > 0 and type(rowColors) == "table" then
    local leftAddr = rowColors[col]
    if type(leftAddr) == "number" then
      initialAddress = string.format("0x%06X", math.floor(leftAddr) + 1)
    end
  end

  self.romPaletteAddressModal:show({
    title = "Enter color address",
    window = win,
    col = col,
    row = row,
    initialAddress = initialAddress,
    onConfirm = function(addressText, targetWindow, targetCol, targetRow)
      local addr, parseErr = Shared.parseHexAddress(addressText)
      if not addr then
        self:setStatus(parseErr)
        self:showToast("error", parseErr)
        return false
      end

      local prevAddr = targetWindow.getRomByteAddress
        and targetWindow:getRomByteAddress(targetCol, targetRow)
        or nil
      if prevAddr == addr then
        -- Address unchanged: do not rebind / wipe user color overrides.
        return true
      end

      local beforeState = Shared.captureRomPaletteAddressUndoState(targetWindow)
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

function AppCoreController:showGalleryRomResultModal(ok, message, detail)
  if not self.galleryRomResultModal then
    return false
  end
  self.galleryRomResultModal:show({
    ok = ok == true,
    message = tostring(message or (ok and "Done." or "Failed.")),
    detail = detail,
  })
  return true
end

--- App-toolbar entry: confirm packed sketches, then build gallery ROM.
function AppCoreController:showGalleryRomConfirmModal()
  local SketchCanvasGalleryRomController = require("controllers.game_art.sketch_canvas_gallery_rom_controller")
  local sketches = SketchCanvasGalleryRomController.collectPackedSketches(self.wm)
  if #sketches < 1 then
    local msg = "No packed sketch canvases with a linked pattern table to export."
    if self.showToast then
      self:showToast("error", msg)
    end
    return self:showGalleryRomResultModal(false, msg)
  end

  local toolsOk, toolsErr = SketchCanvasGalleryRomController.checkCc65Tools()
  if not toolsOk then
    local msg = tostring(toolsErr or "cc65 tools (ca65/ld65) not found")
    if self.showToast then
      self:showToast("error", msg)
    end
    if self.setStatus then
      self:setStatus("Gallery ROM failed: " .. msg)
    end
    return self:showGalleryRomResultModal(false, msg)
  end

  if not self.galleryRomConfirmModal then
    return false
  end
  self.galleryRomConfirmModal:show({
    sketches = sketches,
    app = self,
    onConfirm = function(selected, buildOpts)
      local ok, pathOrErr = SketchCanvasGalleryRomController.buildGalleryRom(
        self,
        selected,
        buildOpts
      )
      if ok then
        self:showGalleryRomResultModal(true, "Wrote gallery ROM:", tostring(pathOrErr))
        if self.setStatus then
          self:setStatus("Gallery ROM: " .. tostring(pathOrErr))
        end
      else
        local err = tostring(pathOrErr or "Gallery ROM build failed")
        if self.showToast then
          self:showToast("error", err)
        end
        self:showGalleryRomResultModal(false, err)
        if self.setStatus then
          self:setStatus("Gallery ROM failed: " .. err)
        end
      end
    end,
  })
  return true
end

--- After New Window → ROM Palette: choose ROM-backed vs sketch free colors.
function AppCoreController:showRomPaletteRoleModal(opts)
  opts = opts or {}
  if not self.romPaletteRoleModal then
    return false
  end
  local allowRom = opts.allowRomRole ~= false and self:hasLoadedROM()
  local windowTitle = opts.windowTitle
  local prevFocusedWin = opts.prevFocusedWin
  self.romPaletteRoleModal:show({
    allowRomRole = allowRom,
    onChoose = function(role)
      if not (self.wm and self.wm.createRomPaletteWindow) then
        return
      end
      local title = windowTitle
      if role == "sketch" then
        title = title or "Sketch palette"
      else
        title = title or "ROM Palette"
      end
      local win = self.wm:createRomPaletteWindow({
        title = title,
        paletteRole = role,
      })
      local Shared = require("controllers.app.core_controller_shared")
      Shared.recordWindowCreateUndo(self, win, prevFocusedWin)
    end,
    onCancel = function()
      -- Cancel = no window (user backed out of type choice).
    end,
  })
  return true
end

end
