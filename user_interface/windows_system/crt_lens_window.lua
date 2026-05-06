-- CRT lens: runtime-only overlay window; content samples the workspace behind it through crtShader at NES resolution.

local Window = require("user_interface.windows_system.window")

local CrtLensWindow = setmetatable({}, { __index = Window })
CrtLensWindow.__index = CrtLensWindow

function CrtLensWindow.new(x, y, zoom, data)
  data = data or {}
  local cellW, cellH = 8, 8
  local cols, rows = 32, 30
  local self = Window.new(x, y, cellW, cellH, cols, rows, zoom or 2, {
    title = data.title or "CRT lens",
    resizable = false,
    visibleCols = cols,
    visibleRows = rows,
  })
  setmetatable(self, CrtLensWindow)

  self.kind = "crt_lens"
  self._runtimeOnly = true
  self.layers = {}
  self.activeLayer = 1
  self._crtLensVisible = false

  -- Scaffold only (future: drive CRT from a specific window layer texture).
  self.crtLensSourceWindowId = nil
  self.crtLensSourceLayerIndex = nil

  return self
end

function CrtLensWindow:contains(px, py)
  if not self._crtLensVisible then
    return false
  end
  return Window.contains(self, px, py)
end

return CrtLensWindow
