-- managers/save_controller.lua
-- Saving ROM: nametables, sprites, CHR banks.

local NametableTilesController = require("controllers.ppu.nametable_tiles_controller")
local SpriteController         = require("controllers.sprite.sprite_controller")
local ChrBackingController     = require("controllers.rom.chr_backing_controller")
local RomSave               = require("romsave")
local DebugController          = require("controllers.dev.debug_controller")

local M = {}

local function applyNametableEditsToROM(app, baseRom)
  local wm = app.wm
  local romWithNametables = baseRom
  local ppuFrameWindows   = wm:getWindowsOfKind("ppu_frame")

  if NametableTilesController and NametableTilesController.writeBackToROM then
    for _, win in ipairs(ppuFrameWindows) do
      local ntLayer
      if win.layers then
        for _, L in ipairs(win.layers) do
          if L.kind == "tile" and L.nametableStartAddr then
            ntLayer = L
            break
          end
        end
      end

      if ntLayer then
        local updated, err = NametableTilesController.writeBackToROM(win, ntLayer, romWithNametables)
        if not updated then
          local title = tostring((win and win.title) or "ppu_frame")
          local msg = string.format("Nametable save error (%s): %s", title, tostring(err))
          print("Nametable save error:" .. tostring(err))
          app:setStatus(msg)
          return nil, msg
        end
        romWithNametables = updated
      end
    end
  end

  return romWithNametables, nil
end

local function applySpriteEditsToROM(app, romAfterNT)
  local romWithSprites = romAfterNT

  if SpriteController and SpriteController.applyDisplacementsToROMForWindows then
    local updated, err = SpriteController.applyDisplacementsToROMForWindows(
      app.wm:getWindows(),
      romAfterNT
    )
    if updated then
      romWithSprites = updated
    elseif err then
      app:setStatus("Sprite save error: " .. tostring(err))
    end
  end

  return romWithSprites
end

local function applyPaletteEditsToROM(app, romAfterSpr)
  local romWithPalettes = romAfterSpr
  local romPaletteWindows = app.wm:getWindowsOfKind("rom_palette")
  local chr = require("chr")

  if not romPaletteWindows or #romPaletteWindows == 0 then
    return romWithPalettes
  end

  -- Apply palette edits from all ROM palette windows
  -- Write all current colors from codes2D (which reflects current state including modifications)
  for _, win in ipairs(romPaletteWindows) do
    if win.paletteData and win.paletteData.romColors and win.codes2D then
      local romColors = win.paletteData.romColors
      local codes2D = win.codes2D
      local editCount = 0
      
      -- Write all current colors from codes2D to ROM
      for row = 0, 3 do  -- 0-indexed rows
        local rowIndex = row + 1  -- 1-indexed for romColors
        if codes2D[row] and romColors[rowIndex] then
          for col = 0, 3 do  -- 0-indexed cols
            local colIndex = col + 1  -- 1-indexed for romColors
            if codes2D[row][col] and romColors[rowIndex][colIndex] then
              local hexCode = codes2D[row][col]
              local romAddr = romColors[rowIndex][colIndex]
              local byteValue = tonumber(hexCode, 16) or 0
              
              local newRom, err = chr.writeByteToAddress(romWithPalettes, romAddr, byteValue)
              if newRom then
                romWithPalettes = newRom
                editCount = editCount + 1
                DebugController.log("debug", "ROM_SAVE", "Applied palette color: row %d, col %d = %s (0x%02X) at 0x%X", 
                  row, col, hexCode, byteValue, romAddr)
              else
                DebugController.log("warning", "ROM_SAVE", "Failed to write palette color at 0x%X: %s", romAddr, tostring(err))
              end
            end
          end
        end
      end
      
      if editCount > 0 then
        DebugController.log("info", "ROM_SAVE", "Applied %d palette colors from ROM palette window '%s'", 
          editCount, win.title or "untitled")
      end
    end
  end

  return romWithPalettes
end

local function writeFinalROM(app, romWithSprites)
  local state = app.appEditState
  local okRom, pathOrErr = pcall(function()
    local ok2, result
    if ChrBackingController.isRomRawMode(state) then
      ok2, result = RomSave.saveRawROM(state.romOriginalPath, romWithSprites)
    else
      ok2, result = RomSave.saveEditedROM(
        state.romOriginalPath,
        romWithSprites,
        state.meta,
        state.chrBanksBytes
      )
    end
    if not ok2 then error(result) end
    return result
  end)

  if okRom then
    app:setStatus("Saved ROM & edits: " .. tostring(pathOrErr))
    state.romRaw     = romWithSprites
    return true
  else
    app:setStatus("Save failed: " .. tostring(pathOrErr or ""))
    return false
  end
end

-- app is AppCoreController instance (needs .appEditState, .wm, .statusText)
function M.saveEdited(app)
  local state  = app.appEditState
  local baseRom = state.romRaw

  if ChrBackingController.isRomRawMode(state) then
    local rebuilt, err = ChrBackingController.rebuildROMFromBacking(state)
    if not rebuilt then
      app:setStatus("No ROM loaded to save: " .. tostring(err or "unknown"))
      return false
    end
    baseRom = rebuilt
  end

  if type(baseRom) ~= "string" or #baseRom == 0 then
    app:setStatus("No ROM loaded to save.")
    return false
  end

  local romAfterNT, ntErr = applyNametableEditsToROM(app, baseRom)
  if not romAfterNT then
    DebugController.log("warning", "ROM_SAVE", "Aborting save due to nametable error: %s", tostring(ntErr))
    return false
  end
  local romAfterSpr = applySpriteEditsToROM(app, romAfterNT)
  local romAfterPal = applyPaletteEditsToROM(app, romAfterSpr)
  return writeFinalROM(app, romAfterPal)
end

return M
