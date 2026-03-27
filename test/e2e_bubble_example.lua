local M = {}

local DEFAULT_PAGE_ONE_TILE_NUMBERS = {
  246, 76, 147, 75, 180, 194, 194, 207,
  194, 202, 209, 193, 174, 82, 102, 194,
  70, 248, 245, 46, 115, 50, 149, 87,
  197, 77, 161, 239, 225, 189, 86, 130,
  203, 223, 206, 142, 67, 56, 231, 194,
  191, 0, 196, 53, 134, 252, 194, 101,
  55, 103, 113, 145, 234, 128, 184, 167,
  117, 122, 179, 99, 148, 85, 157, 205,
}

local DEFAULT_PAGE_ONE_PLACEMENTS = {}
for i, tile in ipairs(DEFAULT_PAGE_ONE_TILE_NUMBERS) do
  local index = i - 1
  DEFAULT_PAGE_ONE_PLACEMENTS[i] = {
    bank = 1,
    tile = tile,
    col = index % 8,
    row = math.floor(index / 8),
  }
end

local function firstReadablePath(candidates)
  for _, path in ipairs(candidates or {}) do
    local file = io.open(path, "rb")
    if file then
      file:close()
      return path
    end
  end
  return nil
end

local function firstLoadablePath(candidates)
  for _, path in ipairs(candidates or {}) do
    local chunk = loadfile(path)
    if chunk then
      return path
    end
  end
  return nil
end

local function readProject(path)
  local chunk, err = loadfile(path)
  if not chunk then
    error("Failed to load bubble example project: " .. tostring(err))
  end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    error("Invalid bubble example project data")
  end
  return data
end

function M.getRomPath()
  return firstReadablePath({
    "test/test_rom.nes",
    "../test/test_rom.nes",
  })
end

function M.getProjectPath()
  return firstLoadablePath({
    "test/test_rom.lua",
    "../test/test_rom.lua",
  })
end

function M.getLoadPath()
  return M.getProjectPath() or M.getRomPath()
end

function M.loadProject()
  local path = M.getProjectPath()
  assert(path, "Could not resolve bubble example project path")
  return readProject(path)
end

function M.getPlacements(project)
  project = project or M.loadProject()
  for _, win in ipairs(project.windows or {}) do
    if win.kind == "static_art" and win.title == "Static Art (tiles)" then
      local layer = win.layers and win.layers[1]
      local items = {}
      for _, item in ipairs((layer and layer.items) or {}) do
        items[#items + 1] = {
          bank = item.bank,
          tile = item.tile,
          col = item.col,
          row = item.row,
        }
      end
      table.sort(items, function(a, b)
        if a.row ~= b.row then
          return a.row < b.row
        end
        return a.col < b.col
      end)
      if #items > 0 then
        return items
      end
      break
    end
  end
  local items = {}
  for i, item in ipairs(DEFAULT_PAGE_ONE_PLACEMENTS) do
    items[i] = {
      bank = item.bank,
      tile = item.tile,
      col = item.col,
      row = item.row,
    }
  end
  return items
end

function M.findBankWindow(app)
  if app and app.winBank then
    return app.winBank
  end
  local wm = app and app.wm
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for _, win in ipairs(windows) do
    if win.kind == "chr" then
      return win
    end
  end
  return nil
end

function M.findStaticWindow(app)
  local wm = app and app.wm
  local windows = wm and wm.getWindows and wm:getWindows() or {}
  for _, win in ipairs(windows) do
    if win.kind == "static_art" and win.title == "Static Art (tiles)" then
      return win
    end
  end
  return nil
end

function M.clearStaticWindow(win)
  if not win then return end
  local layer = win.layers and win.layers[1]
  if not layer then return end
  layer.items = {}
  layer.removedCells = nil
  layer.multiTileSelection = nil
  if win.clearSelected then
    win:clearSelected(1)
  end
end

function M.bankCellForTile(win, tileIndex)
  local cols = (win and win.cols) or 16
  local localTileIndex = math.floor(tonumber(tileIndex) or 0)
  return localTileIndex % cols, math.floor(localTileIndex / cols)
end

function M.prepareBankWindow(win)
  if not win then return nil end
  if win.setCurrentBank then
    win:setCurrentBank(1)
  else
    win.currentBank = 1
  end
  if win.setScroll then
    win:setScroll(0, 0)
  else
    win.scrollCol = 0
    win.scrollRow = 0
  end
  return win
end

return M
