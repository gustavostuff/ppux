-- Minimal "canvas only" view: full logical canvas = 128×72 NES px at 5×, vertical 8px (NES) scroll,
-- CHR specialized toolbar only (draggable). No other UI draws or receives input.

local ShaderPaletteController = require("controllers.palette.shader_palette_controller")
local GridModeUtils = require("controllers.grid_mode_utils")
local ChrCanvasOnlyGrid = require("controllers.chr.chr_canvas_only_grid")

local M = {}

M.SCALE = 5
M.VIEW_W_NES = 128
M.VIEW_H_NES = 72
M.SCROLL_STEP_NES = 8

local function bankPixelH(controller)
  if controller and controller.getCanvasSize then
    local _, h = controller:getCanvasSize()
    return tonumber(h) or 256
  end
  return 256
end

function M.isActive(app)
  return app and app.chrCanvasOnlyWindow ~= nil
end

function M.maxScrollY(app)
  local h = bankPixelH(app and app.chrBankCanvasController)
  local raw = math.max(0, h - M.VIEW_H_NES)
  return math.floor(raw / M.SCROLL_STEP_NES) * M.SCROLL_STEP_NES
end

function M.clampScrollY(app)
  if not M.isActive(app) then
    return
  end
  local maxY = M.maxScrollY(app)
  local step = M.SCROLL_STEP_NES
  local y = math.floor(tonumber(app.chrCanvasOnlyScrollY) or 0)
  y = math.floor(y / step) * step
  if y < 0 then
    y = 0
  end
  if y > maxY then
    y = maxY
  end
  app.chrCanvasOnlyScrollY = y
end

function M.screenToBankPixel(app, mx, my)
  local scrollY = app.chrCanvasOnlyScrollY or 0
  local nesX = math.floor(mx / M.SCALE)
  local nesY = math.floor(my / M.SCALE) + scrollY
  return nesX, nesY
end

function M.screenToGrid(win, app, mx, my)
  local nesX, nesY = M.screenToBankPixel(app, mx, my)
  if nesX < 0 or nesX > M.VIEW_W_NES - 1 or nesY < 0 or nesY > bankPixelH(app.chrBankCanvasController) - 1 then
    return false
  end
  local scrollY = app.chrCanvasOnlyScrollY or 0
  if nesY < scrollY or nesY > scrollY + M.VIEW_H_NES - 1 then
    return false
  end
  local col = math.floor(nesX / 8)
  local row = math.floor(nesY / 8)
  local lx = nesX - col * 8
  local ly = nesY - row * 8
  if col < 0 or col >= (win.cols or 16) or row < 0 or row >= (win.rows or 32) then
    return false
  end
  return true, col, row, lx, ly
end

function M.draw(app)
  local win = app.chrCanvasOnlyWindow
  local controller = app.chrBankCanvasController
  if not (win and controller and app.canvas) then
    return
  end

  M.clampScrollY(app)
  local cw = app.canvas:getWidth()
  local ch = app.canvas:getHeight()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, cw, ch)

  local scrollY = app.chrCanvasOnlyScrollY or 0
  local gridMode = GridModeUtils.normalize(win.showGrid)
  win.showGrid = gridMode

  local li = win.getActiveLayerIndex and win:getActiveLayerIndex() or win.activeLayer or 1
  local layer = win.layers and win.layers[li]
  local layerOpacity = (layer and layer.opacity ~= nil) and layer.opacity or 1.0
  if layerOpacity > 0.001 then
    if gridMode == "chess" then
      ChrCanvasOnlyGrid.drawChessBehindBank(
        app,
        win,
        scrollY,
        M.SCALE,
        M.VIEW_W_NES,
        M.VIEW_H_NES,
        cw,
        ch
      )
    elseif gridMode == "lines" then
      ChrCanvasOnlyGrid.fillBankViewportBackground(
        app,
        win,
        scrollY,
        M.SCALE,
        M.VIEW_W_NES,
        M.VIEW_H_NES,
        cw,
        ch
      )
    end
    ShaderPaletteController.applyShader(true, layer, nil, layerOpacity)
    controller:drawCanvasOnly(
      app.appEditState,
      win,
      0,
      0,
      cw,
      ch,
      scrollY,
      M.SCALE,
      layerOpacity
    )
    ShaderPaletteController.releaseShader()
    if gridMode == "lines" then
      ChrCanvasOnlyGrid.drawLinesOverlay(app, win, scrollY, M.SCALE, cw, ch)
    end
  end

  local tb = win.specializedToolbar
  if tb and tb.updatePosition then
    tb:updatePosition()
  end
  if tb and tb.draw then
    tb:draw()
  end
end

local function pointInToolbarBar(tb, mx, my)
  if not tb then
    return false
  end
  local x = (tonumber(tb.x) or 0) - 1
  local y = tonumber(tb.y) or 0
  local w = math.max(0, tonumber(tb.w) or 0)
  local h = math.max(0, tonumber(tb.h) or 0)
  return mx >= x and my >= y and mx <= x + w and my <= y + h
end

function M.handleMousePressed(app, mx, my, button, wm)
  local win = app.chrCanvasOnlyWindow
  if not win then
    return false
  end
  wm:setFocus(win)

  local tb = win.specializedToolbar
  if tb and tb.updatePosition then
    tb:updatePosition()
  end

  -- Toolbar drag: right or middle button only (LMB stays for icon actions and canvas).
  if tb and (button == 2 or button == 3) and pointInToolbarBar(tb, mx, my) then
    app.chrCanvasOnlyToolbarDrag = {
      button = button,
      dx = mx - (tb.x or 0),
      dy = my - (tb.y or 0),
    }
    return true
  end

  -- Icon buttons and labels: default toolbar behavior (LMB).
  if button == 1 and tb and tb.getButtonAt and tb:getButtonAt(mx, my) then
    if tb.mousepressed and tb:mousepressed(mx, my, button) then
      return true
    end
  end

  if tb and tb.mousepressed and tb:mousepressed(mx, my, button) then
    return true
  end

  local ctx = rawget(_G, "ctx")
  if not ctx then
    return true
  end

  if button == 1 and ctx.getMode and ctx.getMode() == "edit" then
    local ok, col, row, lx, ly = M.screenToGrid(win, app, mx, my)
    if ok and ctx.app and ctx.app.undoRedo then
      if ctx.app.undoRedo.startPaintEvent then
        ctx.app.undoRedo:startPaintEvent()
      end
      if ctx.paintAt then
        ctx.paintAt(win, col, row, lx, ly, false)
      end
      if ctx.setPainting then
        ctx.setPainting(true)
      end
    end
    return true
  end

  if button == 1 and ctx.getMode and ctx.getMode() == "tile" then
    local ok, col, row = M.screenToGrid(win, app, mx, my)
    if ok and win.setSelected then
      local li = (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
      win:setSelected(col, row, li)
    end
    return true
  end

  return true
end

function M.handleMouseMoved(app, mx, my, dx, dy, wm)
  local win = app.chrCanvasOnlyWindow
  if not win then
    return false
  end

  local drag = app.chrCanvasOnlyToolbarDrag
  if drag and love.mouse.isDown(drag.button) then
    app.chrCanvasOnlyToolbarX = mx - drag.dx
    app.chrCanvasOnlyToolbarY = my - drag.dy
    local tb = win.specializedToolbar
    if tb and tb.updatePosition then
      tb:updatePosition()
    end
  else
    local ctx = rawget(_G, "ctx")
    if ctx and ctx.getMode and ctx.getMode() == "edit"
      and ctx.getPainting and ctx.getPainting()
      and love.mouse.isDown(1)
      and not love.keyboard.isDown("f")
      and ctx.paintAt
    then
      local paintAt = ctx.paintAt
      local x0, y0 = mx - (dx or 0), my - (dy or 0)
      local nesX0, nesY0 = M.screenToBankPixel(app, x0, y0)
      local nesX1, nesY1 = M.screenToBankPixel(app, mx, my)
      local ddx = nesX1 - nesX0
      local ddy = nesY1 - nesY0
      local steps = math.max(math.abs(ddx), math.abs(ddy), 1)
      for i = 0, steps do
        local t = (steps == 0) and 0 or (i / steps)
        local nx = math.floor(nesX0 + ddx * t + 0.5)
        local ny = math.floor(nesY0 + ddy * t + 0.5)
        if nx >= 0 and nx <= 127 and ny >= 0 and ny <= bankPixelH(app.chrBankCanvasController) - 1 then
          local scrollY = app.chrCanvasOnlyScrollY or 0
          if ny >= scrollY and ny <= scrollY + M.VIEW_H_NES - 1 then
            local col = math.floor(nx / 8)
            local row = math.floor(ny / 8)
            local lx = nx - col * 8
            local ly = ny - row * 8
            if col >= 0 and col < (win.cols or 16) and row >= 0 and row < (win.rows or 32) then
              paintAt(win, col, row, lx, ly, false)
            end
          end
        end
      end
    end
  end

  local tb = win.specializedToolbar
  if tb and tb.mousemoved then
    tb:mousemoved(mx, my)
  end
  return true
end

function M.handleMouseReleased(app, mx, my, button, wm)
  local win = app.chrCanvasOnlyWindow
  if not win then
    return false
  end
  app.chrCanvasOnlyToolbarDrag = nil

  local tb = win.specializedToolbar
  if tb and tb.updatePosition then
    tb:updatePosition()
  end
  if tb and tb.mousereleased and tb:mousereleased(mx, my, button) then
    return true
  end

  local ctx = rawget(_G, "ctx")
  if ctx and ctx.getMode and ctx.getMode() == "edit" and ctx.getPainting and ctx.getPainting() then
    if ctx.app and ctx.app.undoRedo and ctx.app.undoRedo.finishPaintEvent then
      ctx.app.undoRedo:finishPaintEvent()
    end
    if ctx.setPainting then
      ctx.setPainting(false)
    end
  end
  return true
end

function M.handleWheel(app, dx, dy, mx, my)
  if not M.isActive(app) then
    return false
  end
  local win = app.chrCanvasOnlyWindow
  local tb = win and win.specializedToolbar
  if tb and pointInToolbarBar(tb, mx, my) then
    return true
  end
  -- Match Window:scrollBy / mouse_wheel_controller: positive dy -> scrollRow decreases.
  local step = (dy > 0) and -M.SCROLL_STEP_NES or ((dy < 0) and M.SCROLL_STEP_NES or 0)
  if step ~= 0 then
    app.chrCanvasOnlyScrollY = (app.chrCanvasOnlyScrollY or 0) + step
    M.clampScrollY(app)
  end
  return true
end

function M.getTooltipAt(app, mx, my)
  if not M.isActive(app) then
    return nil
  end
  local win = app.chrCanvasOnlyWindow
  local tb = win and win.specializedToolbar
  if not (tb and tb.getTooltipAt) then
    return nil
  end
  if tb.updatePosition then
    tb:updatePosition()
  end
  return tb:getTooltipAt(mx, my)
end

return M
