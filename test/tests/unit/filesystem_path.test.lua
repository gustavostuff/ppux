local FilesystemPath = require("utils.filesystem_path")

describe("filesystem_path.lua", function()
  it("detects absolute paths including windows drives", function()
    expect(FilesystemPath.isAbsolutePath("/tmp/foo")).toBe(true)
    expect(FilesystemPath.isAbsolutePath("\\windows\\path")).toBe(true)
    expect(FilesystemPath.isAbsolutePath("C:\\Games\\rom.nes")).toBe(true)
    expect(FilesystemPath.isAbsolutePath("D:/Games/rom.nes")).toBe(true)
    expect(FilesystemPath.isAbsolutePath("relative/path")).toBe(false)
    expect(FilesystemPath.isAbsolutePath("rom.nes")).toBe(false)
  end)

  it("leaves absolute paths unchanged when converting", function()
    expect(FilesystemPath.toAbsolutePath("/tmp/My Games/foo")).toBe("/tmp/My Games/foo")
    expect(FilesystemPath.toAbsolutePath("  /tmp/spaced path/bar  ")).toBe("/tmp/spaced path/bar")
  end)

  it("joins relative paths to the working directory", function()
    local previousLove = rawget(_G, "love")
    _G.love = {
      filesystem = {
        getWorkingDirectory = function()
          return "/cwd"
        end,
      },
    }
    local sep = package.config:sub(1, 1)
    expect(FilesystemPath.toAbsolutePath("My Games/rom.nes")).toBe("/cwd" .. sep .. "My Games/rom.nes")
    _G.love = previousLove
  end)
end)
