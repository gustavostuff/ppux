local M = {}

local function contentToCanvasPoint(_, x, y)
  return x, tonumber(y) or 0
end

local function getNewWindowOptionCell(panel, optionIndex)
  local row = 6 + math.floor(((optionIndex or 1) - 1) / 2)
  local col = (((optionIndex or 1) - 1) % 2 == 0) and 1 or 3
  return panel and panel:getCell(col, row)
end

local function newWindowOptionCenter(optionIndex)
  return function(_, currentApp)
    local cell = currentApp.newWindowModal
      and currentApp.newWindowModal.panel
      and getNewWindowOptionCell(currentApp.newWindowModal.panel, optionIndex)
    assert(cell, "expected new window option cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function newWindowOptionCenterByText(text)
  return function(_, currentApp)
    local panel = currentApp.newWindowModal and currentApp.newWindowModal.panel or nil
    assert(panel and panel.cells, "expected new window panel")
    for _, rowCells in pairs(panel.cells or {}) do
      for _, cell in pairs(rowCells or {}) do
        if cell and cell.text == text then
          return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
        end
      end
    end
    error("expected new window option cell for text: " .. tostring(text))
  end
end

local function newWindowModeToggleCenter()
  return function(_, currentApp)
    local cell = currentApp.newWindowModal
      and currentApp.newWindowModal.panel
      and currentApp.newWindowModal.panel:getCell(2, 2)
    assert(cell, "expected new window mode toggle cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function textFieldDemoFieldCenter(fieldKey)
  return function(_, currentApp)
    local modal = assert(currentApp.textFieldDemoModal, "expected text field demo modal")
    assert(modal:isVisible(), "expected text field demo modal to be visible")
    local field = assert(modal[fieldKey], "expected demo field " .. tostring(fieldKey))
    return field.x + math.floor(field.w * 0.5), field.y + math.floor(field.h * 0.5)
  end
end

local function textFieldDemoFieldTextPoint(fieldKey, prefix)
  return function(_, currentApp)
    local modal = assert(currentApp.textFieldDemoModal, "expected text field demo modal")
    assert(modal:isVisible(), "expected text field demo modal to be visible")
    local field = assert(modal[fieldKey], "expected demo field " .. tostring(fieldKey))
    local font = love.graphics.getFont()
    local textPrefix = tostring(prefix or "")
    local padding = 2
    local x = field.x + padding + (font and font:getWidth(textPrefix) or 0)
    local y = field.y + math.floor(field.h * 0.5)
    return x, y
  end
end

local function spriteItemCenter(winResolver, itemResolver, layerResolver)
  return function(_, currentApp, currentRunner)
    local win = assert(winResolver(currentRunner), "expected sprite window")
    local layerIndex = layerResolver and layerResolver(currentRunner) or (win.getActiveLayerIndex and win:getActiveLayerIndex()) or win.activeLayer or 1
    local layer = assert(win.layers and win.layers[layerIndex], "expected sprite layer")
    local itemIndex = itemResolver(currentRunner)
    local sprite = assert(layer.items and layer.items[itemIndex], "expected sprite item")
    local zoom = (win.getZoomLevel and win:getZoomLevel()) or win.zoom or 1
    local worldX = sprite.worldX or sprite.baseX or sprite.x or 0
    local worldY = sprite.worldY or sprite.baseY or sprite.y or 0
    local cellW = win.cellW or 8
    local cellH = win.cellH or 8
    return contentToCanvasPoint(
      currentApp,
      win.x + (worldX + (cellW * 0.5)) * zoom,
      win.y + (worldY + (cellH * 0.5)) * zoom
    )
  end
end

local function toolbarLinkHandleCenter(winResolver)
  return function(_, currentApp, currentRunner)
    local win = assert(winResolver(currentApp, currentRunner), "expected palette window for link handle")
    local toolbar = assert(win.specializedToolbar, "expected specialized toolbar")
    assert(toolbar.getLinkHandleRect, "expected link handle accessor")
    local x, y, w, h = toolbar:getLinkHandleRect()
    assert(type(x) == "number" and type(y) == "number" and type(w) == "number" and type(h) == "number",
      "expected link handle rect")
    if toolbar._dockLayout then
      return x + math.floor(w * 0.5), y + math.floor(h * 0.5)
    end
    return contentToCanvasPoint(currentApp, x + math.floor(w * 0.5), y + math.floor(h * 0.5))
  end
end

local function windowHeaderCenter(winResolver)
  return function(_, currentApp, currentRunner)
    local win = assert(winResolver(currentApp, currentRunner), "expected window for header center")
    assert(win.getHeaderRect, "expected header rect accessor")
    local x, y, w, h = win:getHeaderRect()
    assert(type(x) == "number" and type(y) == "number" and type(w) == "number" and type(h) == "number",
      "expected header rect")
    return contentToCanvasPoint(currentApp, x + math.floor(w * 0.5), y + math.floor(h * 0.5))
  end
end

local function saveOptionCenter(optionIndex)
  return function(_, currentApp)
    local cell = currentApp.saveOptionsModal
      and currentApp.saveOptionsModal.panel
      and currentApp.saveOptionsModal.panel:getCell(1, optionIndex)
    assert(cell, "expected save option cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function menuRowCenter(menuResolver, row)
  return function(_, currentApp, currentRunner)
    local menu = menuResolver(currentApp, currentRunner)
    assert(menu and menu.panel and menu:isVisible(), "expected visible contextual menu")
    local anchorCol = (menu.activeSplitIconCell == true and (tonumber(menu.cols) or 1) > 1) and 2 or 1
    local cell = menu.panel:getCell(anchorCol, row)
    assert(cell, "expected contextual menu row cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function taskbarRootMenu(_, currentRunner)
  local currentApp = currentRunner and currentRunner.app or app
  local taskbar = currentApp and currentApp.taskbar or nil
  return taskbar and taskbar.menuController or nil
end

local function childMenuRowCenter(menuResolver, row)
  return function(_, currentApp, currentRunner)
    local menu = menuResolver(currentApp, currentRunner)
    local childMenu = assert(menu and menu.childMenu, "expected visible child menu")
    local anchorCol = (childMenu.activeSplitIconCell == true and (tonumber(childMenu.cols) or 1) > 1) and 2 or 1
    local cell = childMenu.panel:getCell(anchorCol, row)
    assert(cell, "expected child menu row cell")
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end
end

local function rootMenuItemCenter(menuResolver, itemText)
  return function(_, currentApp, currentRunner)
    local menu = assert(menuResolver(currentApp, currentRunner), "expected visible root menu")
    local items = menu.visibleItems or {}
    local targetRow = nil
    for index, item in ipairs(items) do
      if item and item.text == itemText then
        targetRow = index
        break
      end
    end
    assert(targetRow, "expected root menu item: " .. tostring(itemText))
    return menuRowCenter(menuResolver, targetRow)(nil, currentApp, currentRunner)
  end
end

local function resizeHandleCenter(winResolver)
  return function(_, currentApp, currentRunner)
    local win = assert(winResolver(currentApp, currentRunner), "expected target window for resize handle")
    local x, y, w, h = win:getResizeHandleRect()
    return contentToCanvasPoint(currentApp, x + math.floor(w * 0.5), y + math.floor(h * 0.5))
  end
end

local function taskbarMenuGapPoint(row)
  return function(_, currentApp, currentRunner)
    local menu = assert(taskbarRootMenu(currentApp, currentRunner), "expected visible taskbar root menu")
    local anchorCol = (menu.activeSplitIconCell == true and (tonumber(menu.cols) or 1) > 1) and 2 or 1
    local cell = assert(menu.panel:getCell(anchorCol, row), "expected root menu row cell")
    local childMenu = assert(menu.childMenu, "expected visible child menu")
    local x = math.floor(cell.x + cell.w + 6)
    local y = math.floor(math.min(cell.y, childMenu.y) - 6)
    return x, y
  end
end

local function assertTaskbarChildState(expectedRootText, shouldExist)
  return function(_, currentApp, currentRunner)
    local menu = assert(taskbarRootMenu(currentApp, currentRunner), "expected visible taskbar root menu")
    local childMenu = menu.childMenu
    if shouldExist == false then
      assert(childMenu == nil, "expected taskbar submenu to be hidden")
      return
    end
    assert(childMenu and childMenu:isVisible(), "expected taskbar submenu to be visible")
    if expectedRootText then
      local activeText = menu.activeChildItem and menu.activeChildItem.text or nil
      assert(activeText == expectedRootText, string.format("expected active submenu root %s, got %s", tostring(expectedRootText), tostring(activeText)))
    end
  end
end

M.getNewWindowOptionCell = getNewWindowOptionCell
M.newWindowOptionCenter = newWindowOptionCenter
M.newWindowOptionCenterByText = newWindowOptionCenterByText
M.newWindowModeToggleCenter = newWindowModeToggleCenter
M.textFieldDemoFieldCenter = textFieldDemoFieldCenter
M.textFieldDemoFieldTextPoint = textFieldDemoFieldTextPoint
M.spriteItemCenter = spriteItemCenter
M.toolbarLinkHandleCenter = toolbarLinkHandleCenter
M.windowHeaderCenter = windowHeaderCenter
M.saveOptionCenter = saveOptionCenter
M.menuRowCenter = menuRowCenter
M.taskbarRootMenu = taskbarRootMenu
M.childMenuRowCenter = childMenuRowCenter
M.rootMenuItemCenter = rootMenuItemCenter
M.resizeHandleCenter = resizeHandleCenter
M.taskbarMenuGapPoint = taskbarMenuGapPoint
M.assertTaskbarChildState = assertTaskbarChildState

return M
