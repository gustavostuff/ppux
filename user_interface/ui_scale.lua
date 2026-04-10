local UiScale = {}

UiScale.NORMAL_BUTTON_SIZE = 15
UiScale.NORMAL_MENU_CELL_SIZE = 15
UiScale.NORMAL_WINDOW_HEADER_HEIGHT = 15
UiScale.NORMAL_MODAL_TITLE_HEIGHT = 18

function UiScale.buttonSize()
  return UiScale.NORMAL_BUTTON_SIZE
end

function UiScale.menuCellSize()
  return UiScale.NORMAL_MENU_CELL_SIZE
end

function UiScale.windowHeaderHeight()
  return UiScale.NORMAL_WINDOW_HEADER_HEIGHT
end

function UiScale.taskbarHeight()
  return UiScale.buttonSize()
end

function UiScale.modalButtonHeight()
  return UiScale.buttonSize()
end

function UiScale.modalTitleHeight()
  return UiScale.NORMAL_MODAL_TITLE_HEIGHT
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
  return n == UiScale.NORMAL_BUTTON_SIZE
end

function UiScale.isKnownMenuCellSize(value)
  local n = tonumber(value)
  return n == UiScale.NORMAL_MENU_CELL_SIZE
end

function UiScale.isKnownWindowHeaderHeight(value)
  local n = tonumber(value)
  return n == UiScale.NORMAL_WINDOW_HEADER_HEIGHT
end

function UiScale.isScalableButtonSquare(w, h)
  return UiScale.isKnownButtonSize(w) and UiScale.isKnownButtonSize(h)
end

function UiScale.normalButtonSize()
  return UiScale.NORMAL_BUTTON_SIZE
end

return UiScale
