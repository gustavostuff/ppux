-- Shared temp-file helpers for visible E2E scenarios.

local BubbleExample = require("test.e2e_bubble_example")

local M = {}

function M.copyFile(srcPath, dstPath)
  local src = assert(io.open(srcPath, "rb"))
  local bytes = assert(src:read("*a"))
  src:close()
  local dst = assert(io.open(dstPath, "wb"))
  assert(dst:write(bytes))
  dst:close()
end

function M.removeIfExists(path)
  if path and path ~= "" then
    os.remove(path)
  end
end

function M.cleanupPaths(paths)
  for _, path in ipairs(paths or {}) do
    M.removeIfExists(path)
  end
end

--- Copies test_rom.lua + test_rom.nes into a temp tree:
---   <dir>/invalid_project.lua
---   <dir>/nested/test_rom.{lua,nes}
function M.setupOpenProjectFixture(runner)
  local suffix = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local dir = "/tmp/ppux_e2e_open_project_" .. suffix
  local nested = dir .. "/nested"
  os.execute('mkdir -p "' .. nested .. '"')

  local romSrc = assert(BubbleExample.getRomPath(), "expected test_rom.nes fixture")
  local projSrc = assert(BubbleExample.getProjectPath(), "expected test_rom.lua fixture")

  local romDst = nested .. "/test_rom.nes"
  local projDst = nested .. "/test_rom.lua"
  local invalidDst = dir .. "/invalid_project.lua"

  M.copyFile(romSrc, romDst)
  M.copyFile(projSrc, projDst)

  local invalid = assert(io.open(invalidDst, "w"))
  invalid:write('return "not a project table"\n')
  invalid:close()

  runner.fixtureDir = dir
  runner.fixtureNestedDir = nested
  runner.fixtureProjectPath = projDst
  runner.fixtureInvalidPath = invalidDst
  runner._cleanupPaths = { invalidDst, projDst, romDst }
  return dir, nested, projDst, invalidDst
end

function M.findVisibleSlotForName(modal, name)
  local visible = modal:getVisibleEntries()
  for slotIndex = 1, #visible do
    local entry = visible[slotIndex]
    if entry and entry.name == name then
      return slotIndex
    end
  end
  return nil
end

return M
