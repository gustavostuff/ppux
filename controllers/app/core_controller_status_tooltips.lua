local Shared = require("controllers.app.core_controller_shared")
local BankViewController = require("controllers.chr.bank_view_controller")
local BrushController = require("controllers.input_support.brush_controller")
local SimpleLoadingScreen = require("controllers.app.simple_loading_screen")
local UserInput = require("controllers.input")
local AppTopToolbarController = require("controllers.app.app_top_toolbar_controller")
local ChrCanvasOnlyMode = require("controllers.chr.chr_canvas_only_mode")

return function(AppCoreController)

function AppCoreController:rebuildBankWindowItems()
  if not self.winBank or self.winBank.kind ~= "chr" then return end
  BankViewController.rebuildBankWindowItems(
    self.winBank,
    self.appEditState,
    self.winBank.orderMode or "normal",
    function(text)
      self:setStatus(text)
    end
  )
end

function AppCoreController:paintAt(win, col, row, lx, ly, pickOnly)
  return BrushController.paintPixel(self, win, col, row, lx, ly, pickOnly)
end

function AppCoreController:setChrCanvasOnlyMode(win)
  if not (win and win.kind == "chr") then
    return
  end
  self.chrCanvasOnlyWindow = win
  self.chrCanvasOnlyScrollY = math.floor((win.scrollRow or 0) * 8)
  self.chrCanvasOnlyToolbarX = nil
  self.chrCanvasOnlyToolbarY = nil
  if self.wm and self.wm.setFocus then
    self.wm:setFocus(win)
  end
  ChrCanvasOnlyMode.clampScrollY(self)
end

function AppCoreController:clearChrCanvasOnlyMode()
  if not self.chrCanvasOnlyWindow then
    return
  end
  if self.isPainting and self.undoRedo and self.undoRedo.finishPaintEvent then
    self.undoRedo:finishPaintEvent()
  end
  local win = self.chrCanvasOnlyWindow
  local y = math.floor(tonumber(self.chrCanvasOnlyScrollY) or 0)
  if win.setScroll then
    win:setScroll(win.scrollCol or 0, math.floor(y / 8))
  else
    win.scrollRow = math.floor(y / 8)
  end
  self.chrCanvasOnlyWindow = nil
  self.chrCanvasOnlyScrollY = 0
  self.chrCanvasOnlyToolbarX = nil
  self.chrCanvasOnlyToolbarY = nil
  local c = rawget(_G, "ctx")
  if c and c.setPainting then
    c.setPainting(false)
  end
end

function AppCoreController:setStatus(text)
  if text == nil then return end
  local message = tostring(text)
  if self.toastController and self.toastController:hasActiveInfoWarningErrorToastWithText(message) then
    self.statusText = nil
    self.lastEventText = nil
    return
  end
  self.statusText = message
  self.lastEventText = message
end

function AppCoreController:hasLoadedROM()
  local state = self.appEditState or {}
  if type(state.romSha1) == "string" and state.romSha1 ~= "" then
    return true
  end
  return type(state.romRaw) == "string"
    and #state.romRaw > 0
    and type(state.romOriginalPath) == "string"
    and state.romOriginalPath ~= ""
end

function AppCoreController:showToast(kind, text, opts)
  if not self.toastController then return nil end
  local result = self.toastController:show(kind, text, opts)
  local k = tostring(kind or "info")
  if result and (k == "error" or k == "warning" or k == "info") then
    local msg = tostring(text or "")
    if tostring(self.statusText or "") == msg then
      self.statusText = nil
    end
    if tostring(self.lastEventText or "") == msg then
      self.lastEventText = nil
    end
  end
  return result
end

function AppCoreController:beginSimpleLoading(message)
  self._simpleLoadingActive = true
  self._simpleLoadingMessage = message or "Loading..."
  if SimpleLoadingScreen.resetPresentDebugState then
    SimpleLoadingScreen.resetPresentDebugState()
  end
  return SimpleLoadingScreen.present(self._simpleLoadingMessage, self)
end

function AppCoreController:pulseSimpleLoading(message, opts)
  if message and message ~= "" then
    self._simpleLoadingMessage = message
  end
  if self._simpleLoadingActive ~= true then
    return false
  end
  return SimpleLoadingScreen.present(self._simpleLoadingMessage or "Loading...", self, opts)
end

function AppCoreController:endSimpleLoading()
  self._simpleLoadingActive = false
  self._simpleLoadingMessage = nil
  if SimpleLoadingScreen.logFinalPhaseWork then
    SimpleLoadingScreen.logFinalPhaseWork("endSimpleLoading")
  end
end

function AppCoreController:getTooltipCandidateAt(x, y)
  if x == nil or y == nil then return nil end
  if self._getTooltipsEnabledForSettings and not self:_getTooltipsEnabledForSettings() then
    return nil
  end

  -- Context menus / taskbar main menu sit above windows; do not spawn tooltips
  -- for cells or chrome underneath while the pointer is over the menu.
  if Shared.pointerOverOpenContextMenu(self, x, y) then
    return nil
  end

  local modalOpen = Shared.anyModalVisible(self) or (self.splash and self.splash:isVisible())
  if modalOpen then
    local modalCandidate = Shared.getTopModalTooltipCandidate(self, x, y)
    if modalCandidate then
      return modalCandidate
    end
    return nil
  end

  if ChrCanvasOnlyMode.isActive(self) then
    return ChrCanvasOnlyMode.getTooltipAt(self, x, y)
  end

  local topBarCandidate = AppTopToolbarController.getTooltipAt(self, x, y)
  if topBarCandidate then
    return topBarCandidate
  end

  do
    local WindowLinkVisibility = require("controllers.window.window_link_visibility")
    local handleCandidate = WindowLinkVisibility.getPivotHandleTooltipCandidateAt(self, x, y)
    if handleCandidate then
      return handleCandidate
    end
  end

  if UserInput.getTooltipCandidate then
    local candidate = UserInput.getTooltipCandidate(x, y)
    if candidate then
      return candidate
    end
  end

  if self.taskbar and self.taskbar.getTooltipAt then
    local candidate = self.taskbar:getTooltipAt(x, y)
    if candidate then
      return candidate
    end
  end

  return Shared.getTopWindowTooltipCandidate(self, x, y)
end

end
