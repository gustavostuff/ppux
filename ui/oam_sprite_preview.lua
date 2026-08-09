-- OAM sprite preview for the Add/Edit sprite modal.
-- NES OAM is four consecutive bytes (each 0x00-0xFF):
--   +0 Y, +1 tile (logical PT index when linked), +2 attr (pal=low2; bit6 H; bit7 V), +3 X.
-- Renders one 2x preview per selected OAM start; ants tint matches the hex-group color.

local Draw = require("utils.draw_utils")
local SpriteHydrationController = require("controllers.sprite.hydration_controller")
local SpriteLayerDraw = require("ui.windows_system.sprite_layer_draw")
local images = require("images")
local colors = require("app_colors")

local M = {}
M.__index = M

local PREVIEW_SCALE = 2
local TILE = 8
local PREVIEW_GAP = 6
local ANTS = {
  stepPx = 1,
  intervalSeconds = 0.1,
}

local function romHasFourBytes(romRaw, addr)
  if type(romRaw) ~= "string" or type(addr) ~= "number" then
    return false
  end
  addr = math.floor(addr)
  if addr < 0 then
    return false
  end
  return (addr + 3) < #romRaw
end

--- Copy layer-sprite appearance overrides onto a hydrate seed so the preview
--- matches what the OAM/PPU layer draws (user flip + paletteNumber).
local function applyAppearanceSeed(dst, src)
  if not (dst and src) then
    return
  end
  if src._mirrorXOverrideSet == true then
    dst._mirrorXOverrideSet = true
    dst.mirrorX = src.mirrorX == true
  end
  if src._mirrorYOverrideSet == true then
    dst._mirrorYOverrideSet = true
    dst.mirrorY = src.mirrorY == true
  end
  if src.paletteNumber ~= nil then
    dst.paletteNumber = src.paletteNumber
  end
end

local function itemIsDrawable(item, mode)
  if not (item and item.topRef and type(item.topRef.draw) == "function") then
    return false
  end
  if mode == "8x16" then
    return item.botRef ~= nil and type(item.botRef.draw) == "function"
  end
  return true
end

local function copyColor(c, alpha)
  if type(c) ~= "table" then
    return { 1, 1, 1, alpha or 1 }
  end
  return { c[1] or 1, c[2] or 1, c[3] or 1, alpha or c[4] or 1 }
end

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({
    x = 0,
    y = 0,
    w = 80,
    h = 48,
    romRaw = "",
    spriteLayer = nil,
    tilesPool = nil,
    appEditState = nil,
    appearanceSprite = nil,
    selectedAddr = 0,
    selectedStarts = { 0 },
    groupColors = {},
    _slots = {},
  }, M)
  return self
end

function M:setPosition(x, y)
  self.x = math.floor(tonumber(x) or 0)
  self.y = math.floor(tonumber(y) or 0)
end

function M:setSize(w, h)
  if type(w) == "number" then
    self.w = math.floor(w)
  end
  if type(h) == "number" then
    self.h = math.floor(h)
  end
end

function M:contains(px, py)
  return px >= self.x and px < self.x + self.w
    and py >= self.y and py < self.y + self.h
end

function M:setContext(opts)
  opts = opts or {}
  self.romRaw = type(opts.romRaw) == "string" and opts.romRaw or ""
  self.spriteLayer = opts.spriteLayer
  self.tilesPool = opts.tilesPool
  self.appEditState = opts.appEditState
  self.appearanceSprite = opts.appearanceSprite
  self:refresh()
end

function M:setSelectedAddr(addr)
  addr = math.floor(tonumber(addr) or 0)
  self.selectedAddr = addr
  self.selectedStarts = { addr }
  self:refresh()
end

--- starts: list of OAM start addresses; groupColors[i] optional tint for ants.
function M:setSelectedStarts(starts, groupColors)
  local list = {}
  if type(starts) == "table" then
    for i = 1, #starts do
      list[#list + 1] = math.floor(tonumber(starts[i]) or 0)
    end
  end
  if #list == 0 then
    list[1] = math.floor(tonumber(self.selectedAddr) or 0)
  end
  self.selectedStarts = list
  self.selectedAddr = list[#list]
  self.groupColors = type(groupColors) == "table" and groupColors or {}
  self:refresh()
end

function M:canDrawSprite()
  for _, slot in ipairs(self._slots) do
    if slot.canDraw then
      return true
    end
  end
  return false
end

function M:hasValidOamBytes()
  return romHasFourBytes(self.romRaw, self.selectedAddr)
end

function M:_buildSlot(addr, color)
  local slot = {
    addr = addr,
    item = nil,
    canDraw = false,
    antsColor = copyColor(color or colors.white, 1),
  }
  local layer = self.spriteLayer
  if not (layer and layer.kind == "sprite") then
    return slot
  end
  if not romHasFourBytes(self.romRaw, addr) then
    return slot
  end
  if not self.tilesPool then
    return slot
  end

  local mode = layer.mode or "8x8"
  local appearance = self.appearanceSprite
  if appearance
      and appearance.removed ~= true
      and type(appearance.startAddr) == "number"
      and appearance.startAddr == addr
      and itemIsDrawable(appearance, mode) then
    slot.item = appearance
    slot.canDraw = true
    return slot
  end

  local seed = { startAddr = addr }
  applyAppearanceSeed(seed, appearance)
  local tempLayer = {
    kind = "sprite",
    mode = mode,
    patternTable = layer.patternTable,
    linkedPatternTableWindowId = layer.linkedPatternTableWindowId,
    items = { seed },
  }
  SpriteHydrationController.hydrateSpriteLayer(tempLayer, {
    romRaw = self.romRaw,
    tilesPool = self.tilesPool,
    appEditState = self.appEditState,
    keepWorld = false,
  })
  local item = tempLayer.items[1]
  slot.item = item
  slot.canDraw = itemIsDrawable(item, mode)
  return slot
end

function M:refresh()
  self._slots = {}
  local starts = self.selectedStarts or { self.selectedAddr }
  for i = 1, #starts do
    self._slots[i] = self:_buildSlot(starts[i], self.groupColors[i])
  end
end

function M:_previewPixelSize()
  local mode = (self.spriteLayer and self.spriteLayer.mode) or "8x8"
  local pw = TILE * PREVIEW_SCALE
  local ph = (mode == "8x16") and (TILE * 2 * PREVIEW_SCALE) or (TILE * PREVIEW_SCALE)
  return pw, ph
end

function M:_layoutMetrics()
  local pw, ph = self:_previewPixelSize()
  local n = math.max(1, #(self._slots or {}))
  local availW = math.max(pw, self.w - 4)
  local per = pw + PREVIEW_GAP
  local cols = math.max(1, math.floor((availW + PREVIEW_GAP) / per))
  if cols > n then
    cols = n
  end
  local rows = math.ceil(n / cols)
  return pw, ph, cols, rows, n
end

--- Preferred panel cell height for the current selection count / wrap.
function M:preferredHeight()
  local _, ph, _, rows = self:_layoutMetrics()
  return rows * (ph + PREVIEW_GAP) - PREVIEW_GAP + 8
end

function M:_drawOne(slot, boxX, boxY, pw, ph)
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", boxX - 2, boxY - 2, pw + 4, ph + 4)

  if slot.canDraw and slot.item and self.spriteLayer then
    love.graphics.push()
    love.graphics.translate(boxX, boxY)
    love.graphics.scale(PREVIEW_SCALE, PREVIEW_SCALE)
    SpriteLayerDraw.drawDefaultSpriteBody(
      self.spriteLayer,
      slot.item,
      true,
      TILE,
      TILE,
      self.spriteLayer.mode or "8x8",
      1.0,
      self.romRaw
    )
    love.graphics.pop()
  else
    local icon = images and images.icons and images.icons.chrome and images.icons.chrome.icon_x
    if icon then
      local iw = (icon.getWidth and icon:getWidth()) or 16
      local ih = (icon.getHeight and icon:getHeight()) or 16
      local ix = boxX + math.floor((pw - iw) * 0.5)
      local iy = boxY + math.floor((ph - ih) * 0.5)
      love.graphics.setColor(colors.white)
      love.graphics.draw(icon, ix, iy)
    else
      love.graphics.setColor(1, 0.3, 0.3, 1)
      love.graphics.line(boxX + 2, boxY + 2, boxX + pw - 2, boxY + ph - 2)
      love.graphics.line(boxX + pw - 2, boxY + 2, boxX + 2, boxY + ph - 2)
    end
  end

  local ants = slot.antsColor or colors.white
  love.graphics.setColor(ants[1], ants[2], ants[3], ants[4] or 1)
  if images and images.pattern_a then
    Draw.drawRepeatingImageAnimated(
      images.pattern_a,
      math.floor(boxX),
      math.floor(boxY),
      pw,
      ph,
      ANTS
    )
  else
    love.graphics.rectangle("line", boxX, boxY, pw, ph)
  end
end

function M:draw()
  local pw, ph, cols, rows, n = self:_layoutMetrics()
  local totalW = cols * pw + math.max(0, cols - 1) * PREVIEW_GAP
  local totalH = rows * ph + math.max(0, rows - 1) * PREVIEW_GAP
  local originX = self.x + math.floor((self.w - totalW) * 0.5)
  local originY = self.y + math.floor((self.h - totalH) * 0.5)

  for i = 1, n do
    local slot = self._slots[i]
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local boxX = originX + col * (pw + PREVIEW_GAP)
    local boxY = originY + row * (ph + PREVIEW_GAP)
    self:_drawOne(slot, boxX, boxY, pw, ph)
  end

  love.graphics.setColor(colors.white)
end

return M
