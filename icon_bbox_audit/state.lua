local State = {}

function State.new()
  return {
    iconsDir = nil,
    scanned = {},
    oversized = {},
    scanErrors = {},
    scrollY = 0,
    maxScroll = 0,
    canvas = nil,
    uiFont = nil,
  }
end

function State.resetScan(state)
  state.scanned = {}
  state.oversized = {}
  state.scanErrors = {}
  state.scrollY = 0
  state.maxScroll = 0
end

function State.clampScroll(state)
  if state.scrollY > 0 then
    state.scrollY = 0
  end
  local minY = -math.max(0, state.maxScroll or 0)
  if state.scrollY < minY then
    state.scrollY = minY
  end
end

return State
