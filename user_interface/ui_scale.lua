local UiScale = {}

UiScale.NORMAL_BUTTON_SIZE = 15
UiScale.COMPACT_BUTTON_SIZE = 9

UiScale.NORMAL_MENU_CELL_SIZE = 15
UiScale.COMPACT_MENU_CELL_SIZE = 9

UiScale.NORMAL_WINDOW_HEADER_HEIGHT = 15
UiScale.COMPACT_WINDOW_HEADER_HEIGHT = 9

UiScale.NORMAL_MODAL_TITLE_HEIGHT = 18
UiScale.COMPACT_MODAL_TITLE_HEIGHT = 9

UiScale._compactMode = false

function UiScale.setCompactMode(enabled)
  UiScale._compactMode = (enabled == true)
  return UiScale._compactMode
end

function UiScale.isCompactMode()
  return UiScale._compactMode == true
end

function UiScale.buttonSize()
  if UiScale.isCompactMode() then
    return UiScale.COMPACT_BUTTON_SIZE
  end
  return UiScale.NORMAL_BUTTON_SIZE
end

function UiScale.menuCellSize()
  if UiScale.isCompactMode() then
    return UiScale.COMPACT_MENU_CELL_SIZE
  end
  return UiScale.NORMAL_MENU_CELL_SIZE
end

function UiScale.windowHeaderHeight()
  if UiScale.isCompactMode() then
    return UiScale.COMPACT_WINDOW_HEADER_HEIGHT
  end
  return UiScale.NORMAL_WINDOW_HEADER_HEIGHT
end

function UiScale.taskbarHeight()
  return UiScale.buttonSize()
end

function UiScale.modalButtonHeight()
  return UiScale.buttonSize()
end

function UiScale.modalTitleHeight()
  if UiScale.isCompactMode() then
    return UiScale.COMPACT_MODAL_TITLE_HEIGHT
  end
  return UiScale.NORMAL_MODAL_TITLE_HEIGHT
end

function UiScale.modalTextOffsetY()
  if UiScale.isCompactMode() then
    return 0
  end
  return 1
end

function UiScale.mapStandardButtonSize(value)
  local n = tonumber(value)
  if UiScale.isKnownButtonSize(n) then
    return UiScale.buttonSize()
  end
  return n
end

function UiScale.isKnownButtonSize(value)
  local n = tonumber(value)
  return n == UiScale.NORMAL_BUTTON_SIZE or n == UiScale.COMPACT_BUTTON_SIZE
end

function UiScale.isKnownMenuCellSize(value)
  local n = tonumber(value)
  return n == UiScale.NORMAL_MENU_CELL_SIZE or n == UiScale.COMPACT_MENU_CELL_SIZE
end

function UiScale.isKnownWindowHeaderHeight(value)
  local n = tonumber(value)
  return n == UiScale.NORMAL_WINDOW_HEADER_HEIGHT or n == UiScale.COMPACT_WINDOW_HEADER_HEIGHT
end

function UiScale.isScalableButtonSquare(w, h)
  return UiScale.isKnownButtonSize(w) and UiScale.isKnownButtonSize(h)
end

function UiScale.normalButtonSize()
  return UiScale.NORMAL_BUTTON_SIZE
end

return UiScale
