local ToastController = require("controllers.ui.toast_controller")
local Timer = require("utils.timer_utils")

describe("toast_controller.lua", function()
  local fakeNow = 0
  local oldGetTime = nil

  beforeEach(function()
    if not love.timer then
      love.timer = {}
    end
    oldGetTime = love.timer.getTime
    fakeNow = 1000
    love.timer.getTime = function()
      return fakeNow
    end
    Timer.clear()
    Timer.clearAllMarks()
  end)

  afterEach(function()
    love.timer.getTime = oldGetTime
    Timer.clear()
    Timer.clearAllMarks()
  end)

  local function advance(controller, dt)
    fakeNow = fakeNow + (dt or 0)
    controller:update(dt or 0)
  end

  local function makeController()
    local app = {
      canvas = {
        getWidth = function() return 320 end,
        getHeight = function() return 240 end,
      },
      taskbar = {
        getTopY = function() return 225 end,
      },
    }
    local controller = ToastController.new(app)
    controller:updateLayout(320, 240)
    return controller
  end

  it("stacks newest toast closest to the taskbar", function()
    local controller = makeController()
    local first = controller:show("info", "Saved project")
    advance(controller, 0.2)

    local second = controller:show("warning", "Removed layer")
    advance(controller, 0.2)

    expect(#controller.toasts).toBe(2)
    expect(controller.toasts[1]).toBe(second)
    expect(controller.toasts[2]).toBe(first)
    expect(controller.toasts[1].targetY).toBeGreaterThan(controller.toasts[2].targetY)
  end)

  it("auto-dismisses toasts after fade-out completes", function()
    local controller = makeController()
    controller:show("info", "Saved project")

    advance(controller, 3.05)
    expect(#controller.toasts).toBe(1)
    expect(controller.toasts[1].alpha).toBeLessThan(1)

    advance(controller, 0.5)

    expect(#controller.toasts).toBe(0)
  end)

  it("fades toast alpha over the last 0.5 seconds", function()
    local controller = makeController()
    controller:show("info", "Saved project")

    advance(controller, 3.25)
    expect(#controller.toasts).toBe(1)
    expect(controller.toasts[1].alpha).toBeGreaterThan(0.4)
    expect(controller.toasts[1].alpha).toBeLessThan(0.6)
  end)

  it("closes a toast when clicking its body", function()
    local controller = makeController()
    local toast = controller:show("error", "Export failed")
    advance(controller, 0.25)

    local x = math.floor((toast.x or toast.targetX) + 8)
    local y = math.floor((toast.y or toast.targetY) + 8)

    expect(controller:mousepressed(x, y, 1)).toBeTruthy()
    expect(controller:mousereleased(x, y, 1)).toBeTruthy()

    advance(controller, 0.2)
    expect(#controller.toasts).toBe(0)
  end)

  it("closes a toast when clicking its close icon", function()
    local controller = makeController()
    local toast = controller:show("warning", "Removed window")
    advance(controller, 0.25)

    local x, y, w, h = controller:_closeRect(toast)
    local clickX = x + math.floor(w / 2)
    local clickY = y + math.floor(h / 2)

    expect(controller:mousepressed(clickX, clickY, 1)).toBeTruthy()
    expect(controller:mousereleased(clickX, clickY, 1)).toBeTruthy()

    advance(controller, 0.2)
    expect(#controller.toasts).toBe(0)
  end)

  it("can expand toast width beyond the old max for long text", function()
    local controller = makeController()
    local longText = string.rep("long toast text ", 18)
    local toast = controller:show("warning", longText)

    expect(toast).toBeTruthy()
    expect(toast.w).toBeGreaterThan(260)
    expect(toast.w).toBeLessThan(521)
  end)

  it("hasActiveInfoWarningErrorToastWithText matches info, warning, and error only", function()
    local controller = makeController()
    expect(controller:hasActiveInfoWarningErrorToastWithText("Hello")).toBe(false)
    expect(controller:hasActiveInfoWarningErrorToastWithText("")).toBe(false)
    controller:show("info", "Hello")
    expect(controller:hasActiveInfoWarningErrorToastWithText("Hello")).toBe(true)
    controller:show("success", "Other")
    expect(controller:hasActiveInfoWarningErrorToastWithText("Other")).toBe(false)
    controller:show("warning", "Other")
    expect(controller:hasActiveInfoWarningErrorToastWithText("Other")).toBe(true)
  end)

  it("truncates with middle ellipsis when text does not fit even expanded width", function()
    local controller = makeController()
    local veryLongText = "Saved project: /home/g/Documents/super_long_workspace_name/projects/nes/very/deep/folder/structure/my_project_file_with_a_long_name.ppux"
    controller:show("error", veryLongText)

    local capturedText = nil
    local oldPrint = love.graphics.print
    local ok, err = pcall(function()
      love.graphics.print = function(text)
        if capturedText == nil then
          capturedText = text
        end
      end
      controller:draw(320, 240)
    end)
    love.graphics.print = oldPrint
    if not ok then error(err) end

    expect(capturedText).toBeTruthy()
    expect(capturedText).toNotBe(veryLongText)
    expect(string.find(capturedText, "...", 1, true)).toNotBe(nil)
    expect(string.sub(capturedText, 1, 6)).toBe(string.sub(veryLongText, 1, 6))
    expect(string.sub(capturedText, -5)).toBe(string.sub(veryLongText, -5))
  end)
end)
