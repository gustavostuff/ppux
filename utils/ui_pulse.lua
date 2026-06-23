-- Shared timing for UI oscillations (taskbar focus backdrop, edit-mode pencil cursor shader, etc.).
-- Angular frequency ω (rad/s): one full cycle every (2π/ω) seconds.

local LoveCompat = require("utils.love_compat")

local M = {}

--- Must stay in sync with the `sin(u_time * ω)` term compiled into `utils/draw_utils` cursor shader.
M.OMEGA_RAD_PER_SEC = 8

function M.nowSeconds()
  return LoveCompat.getTimeOr(0)
end

--- Luminance 0=black → 1=white → 0 with the same ω as the pencil black-channel pulse (cos vs sin = 90° phase; same speed).
function M.luminanceBackdrop01(t)
  local w = M.OMEGA_RAD_PER_SEC
  return (1 - math.cos(w * t)) / 2
end

return M
