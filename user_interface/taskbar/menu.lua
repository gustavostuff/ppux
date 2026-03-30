local ContextualMenuController = require("controllers.ui.contextual_menu_controller")
local images = require("images")

local M = {}

function M.install(Taskbar, Helpers)
  function Taskbar:_initMenu()
    self.menuController = ContextualMenuController.new({
      getBounds = function()
        return {
          w = self.x + self.w,
          h = self.y + self.h,
        }
      end,
      cols = 8,
      cellW = 15,
      cellH = 15,
      padding = 0,
      colGap = 0,
      rowGap = 1,
      splitIconCell = true,
    })

    local function closeMenu()
      if self.menuController then
        self.menuController:hide()
      end
    end

    local function actionSave()
      closeMenu()
      if self.app and self.app.showSaveOptionsModal and self.app:showSaveOptionsModal() then
        Helpers.setLastEvent(self.app, "Opened save options")
      end
    end

    local function actionNewWindow()
      closeMenu()
      if self.app and self.app.showNewWindowModal and self.app:showNewWindowModal() then
        Helpers.setLastEvent(self.app, "Opened new window modal")
      end
    end

    local function actionSettings()
      closeMenu()
      if self.app and self.app.showSettingsModal then
        self.app:showSettingsModal()
        Helpers.setLastEvent(self.app, "Opened settings")
      end
    end

    local function actionCloseProject()
      closeMenu()
      if self.app and self.app.requestCloseProject then
        self.app:requestCloseProject()
        Helpers.setLastEvent(self.app, "Closed project")
      end
    end

    local function actionQuit()
      closeMenu()
      if not self.app then return end
      if self.app.handleQuitRequest and self.app:handleQuitRequest() then
        Helpers.setLastEvent(self.app, "Opened quit confirmation")
        return
      end
      love.event.quit()
    end

    local function actionCollapseAll()
      closeMenu()
      local wm = self.app and self.app.wm
      local canvas = self.app and self.app.canvas
      if wm and wm.collapseAll and canvas then
        local areaX = 30
        local areaY = 30
        local areaH = math.max(1, self.y - areaY - 8)
        wm:collapseAll({
          areaX = areaX,
          areaY = areaY,
          areaH = areaH,
          gapX = 8,
          gapY = 2,
        })
        Helpers.setLastEvent(self.app, "Windows collapsed and stacked")
      end
    end

    local function actionExpandAll()
      closeMenu()
      local wm = self.app and self.app.wm
      if wm and wm.expandAll and wm:expandAll() then
        Helpers.setLastEvent(self.app, "Windows expanded")
      end
    end

    local function actionSortByTitle()
      closeMenu()
      if self.sortAlphaButton and self.sortAlphaButton.action then
        self.sortAlphaButton.action()
      end
    end

    local function actionSortByType()
      closeMenu()
      if self.sortKindButton and self.sortKindButton.action then
        self.sortKindButton.action()
      end
    end

    local function actionMinimizeAll()
      closeMenu()
      local wm = self.app and self.app.wm
      if wm and wm.minimizeAll and wm:minimizeAll() then
        Helpers.setLastEvent(self.app, "Windows minimized")
      end
    end

    local function actionMaximizeAll()
      closeMenu()
      local wm = self.app and self.app.wm
      if wm and wm.maximizeAll and wm:maximizeAll() then
        Helpers.setLastEvent(self.app, "Windows restored")
      end
    end

    self._menuActions = {
      expandAll = actionExpandAll,
      collapseAll = actionCollapseAll,
      sortByTitle = actionSortByTitle,
      sortByType = actionSortByType,
      minimizeAll = actionMinimizeAll,
      maximizeAll = actionMaximizeAll,
      newWindow = actionNewWindow,
      save = actionSave,
      settings = actionSettings,
      closeProject = actionCloseProject,
      quit = actionQuit,
    }
    self._menuIcons = {
      expandAll = images.icons.icon_cascade_all,
      collapseAll = images.icons.icon_collapse_all,
      minimizeAll = images.icons.min_all,
      maximizeAll = images.icons.max_all,
      newWindow = images.icons.icon_new_window,
      save = images.icons.save,
      settings = images.icons.settings,
      windows = images.icons.icon_windows,
      recentProjects = images.icons.icon_clock,
      closeProject = images.icons.icon_x,
      quit = images.icons.icon_quit,
    }
    self:_refreshMenuItems()
  end

  function Taskbar:_getMenuAnchor()
    local menuH = (self.menuController and self.menuController.panel and self.menuController.panel.h) or 0
    local menuW = (self.menuController and self.menuController.panel and self.menuController.panel.w) or 0
    local panelX = self.menuButton and self.menuButton.x or self.x
    local panelY = self.y - menuH
    if panelY < 0 then
      panelY = 0
    end
    if panelX + menuW > self.x + self.w then
      panelX = math.max(self.x, self.x + self.w - menuW)
    end
    return panelX, panelY
  end

  function Taskbar:_buildRecentProjectMenuItems()
    local recent = (self.app and self.app.getRecentProjects and self.app:getRecentProjects()) or {}
    local entries = {}
    local stemCounts = {}

    for _, path in ipairs(recent) do
      local _, stem = Helpers.splitPath(path)
      stemCounts[stem] = (stemCounts[stem] or 0) + 1
    end

    for _, path in ipairs(recent) do
      local dir, stem = Helpers.splitPath(path)
      local label = stem
      if (stemCounts[stem] or 0) > 1 then
        local folder = Helpers.baseName(dir)
        label = ((folder ~= "" and folder) or dir or "?") .. "/" .. stem
      end
      entries[#entries + 1] = {
        text = label,
        callback = function()
          if self.app and self.app.openRecentProject then
            self.app:openRecentProject(path)
          end
        end,
      }
    end

    return entries
  end

  function Taskbar:_buildMainMenuItems()
    local hasRom = Helpers.appHasLoadedRom(self.app)
    local recentItems = self:_buildRecentProjectMenuItems()
    local windowsItems = {
      {
        icon = self._menuIcons and self._menuIcons.newWindow or nil,
        text = "New Window",
        enabled = hasRom,
        callback = self._menuActions and self._menuActions.newWindow or nil,
      },
      {
        icon = self._menuIcons and self._menuIcons.expandAll or nil,
        text = "Expand all",
        enabled = hasRom,
        callback = self._menuActions and self._menuActions.expandAll or nil,
      },
      {
        icon = self._menuIcons and self._menuIcons.collapseAll or nil,
        text = "Collapse all",
        enabled = hasRom,
        callback = self._menuActions and self._menuActions.collapseAll or nil,
      },
      {
        icon = self.sortAlphaButton and self.sortAlphaButton.icon or nil,
        text = "Sort by title",
        enabled = hasRom,
        callback = self._menuActions and self._menuActions.sortByTitle or nil,
      },
      {
        icon = self.sortKindButton and self.sortKindButton.icon or nil,
        text = "Sort by kind",
        enabled = hasRom,
        callback = self._menuActions and self._menuActions.sortByType or nil,
      },
      {
        icon = self._menuIcons and self._menuIcons.minimizeAll or nil,
        text = "Minimize all",
        enabled = hasRom,
        callback = self._menuActions and self._menuActions.minimizeAll or nil,
      },
      {
        icon = self._menuIcons and self._menuIcons.maximizeAll or nil,
        text = "Maximize all",
        enabled = hasRom,
        callback = self._menuActions and self._menuActions.maximizeAll or nil,
      },
    }

    return {
      {
        icon = self._menuIcons and self._menuIcons.recentProjects or nil,
        text = "Recent Projects",
        enabled = #recentItems > 0,
        children = (#recentItems > 0) and function()
          return self:_buildRecentProjectMenuItems()
        end or nil,
      },
      {
        icon = self._menuIcons and self._menuIcons.windows or nil,
        text = "Windows",
        enabled = hasRom,
        children = hasRom and function()
          return windowsItems
        end or nil,
      },
      {
        icon = self._menuIcons and self._menuIcons.quit or nil,
        text = "Quit",
        enabled = true,
        callback = self._menuActions and self._menuActions.quit or nil,
      },
      {
        icon = self._menuIcons and self._menuIcons.closeProject or nil,
        text = "Close Project",
        enabled = hasRom,
        callback = self._menuActions and self._menuActions.closeProject or nil,
      },
      {
        icon = self._menuIcons and self._menuIcons.settings or nil,
        text = "Settings",
        enabled = true,
        callback = self._menuActions and self._menuActions.settings or nil,
      },
      {
        icon = self._menuIcons and self._menuIcons.save or nil,
        text = "Save",
        enabled = hasRom,
        callback = self._menuActions and self._menuActions.save or nil,
      },
    }
  end

  function Taskbar:_refreshMenuItems()
    if not self.menuController then
      return
    end
    self.menuController:setItems(self:_buildMainMenuItems())
    if self.menuController:isVisible() then
      local panelX, panelY = self:_getMenuAnchor()
      self.menuController:setPosition(panelX, panelY)
    end
  end

  function Taskbar:_refreshMenuAvailability()
    self:_refreshMenuItems()
  end

  function Taskbar:_refreshMenuSortCells()
    self:_refreshMenuItems()
  end

  function Taskbar:toggleMenu()
    if not self.menuController then
      return false
    end
    self:_refreshMenuItems()
    local panelX, panelY = self:_getMenuAnchor()
    return self.menuController:toggleAt(panelX, panelY, self:_buildMainMenuItems())
  end
end

return M
