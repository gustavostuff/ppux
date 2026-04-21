local ContextualMenuController = require("controllers.ui.contextual_menu_controller")

describe("contextual_menu_controller.lua", function()
  local fakeNow = 0
  local oldGetTime = nil

  beforeEach(function()
    if not love.timer then
      love.timer = {}
    end
    oldGetTime = love.timer.getTime
    fakeNow = 100
    love.timer.getTime = function()
      return fakeNow
    end
  end)

  afterEach(function()
    love.timer.getTime = oldGetTime
  end)

  local function makeMenu()
    local menu = ContextualMenuController.new({
      getBounds = function()
        return { w = 320, h = 240 }
      end,
      cellH = 15,
      childHoverGraceSeconds = 0.18,
    })

    menu:showAt(20, 20, {
      {
        text = "Parent",
        children = {
          { text = "Child" },
        },
      },
      {
        text = "Leaf",
      },
    })

    return menu
  end

  local function cellCenter(cell)
    return cell.x + math.floor(cell.w * 0.5), cell.y + math.floor(cell.h * 0.5)
  end

  it("keeps a submenu open briefly while crossing the gap toward it", function()
    local menu = makeMenu()
    local parentCell = assert(menu.panel:getCell(1, 1), "expected parent cell")
    local px, py = cellCenter(parentCell)

    menu:mousemoved(px, py)
    expect(menu.childMenu).toBeTruthy()

    menu:mousemoved(parentCell.x + parentCell.w + 4, parentCell.y - 4)
    expect(menu.childMenu).toBeTruthy()

    fakeNow = fakeNow + 0.10
    menu:update()
    expect(menu.childMenu).toBeTruthy()

    fakeNow = fakeNow + 0.10
    menu:update()
    expect(menu.childMenu).toBeNil()
  end)

  it("keeps the submenu open briefly when hovering a different leaf item", function()
    local menu = makeMenu()
    menu:setItems({
      {
        text = "Parent",
        children = {
          { text = "Child" },
        },
      },
      {
        text = "Leaf",
      },
    })
    local parentCell = assert(menu.panel:getCell(1, 1), "expected parent cell")
    local leafCell = assert(menu.panel:getCell(1, 2), "expected leaf cell")
    local px, py = cellCenter(parentCell)
    local lx, ly = cellCenter(leafCell)

    menu:mousemoved(px, py)
    expect(menu.childMenu).toBeTruthy()

    menu:mousemoved(lx, ly)
    expect(menu.childMenu).toBeTruthy()

    fakeNow = fakeNow + 0.10
    menu:update()
    expect(menu.childMenu).toBeTruthy()

    fakeNow = fakeNow + 0.10
    menu:update()
    expect(menu.childMenu).toBeNil()
  end)

  it("does not open when every item is disabled (nothing renderable)", function()
    local menu = ContextualMenuController.new({
      getBounds = function()
        return { w = 320, h = 240 }
      end,
      cellH = 15,
    })
    local opened = menu:showAt(10, 10, {
      { text = "Hidden", enabled = false },
    })
    expect(opened).toBe(false)
    expect(menu:isVisible()).toBe(false)
  end)

  it("waits briefly before switching to a different parent item with children", function()
    local menu = makeMenu()
    menu:setItems({
      {
        text = "Parent A",
        children = {
          { text = "Child A" },
        },
      },
      {
        text = "Parent B",
        children = {
          { text = "Child B" },
        },
      },
    })
    local firstCell = assert(menu.panel:getCell(1, 1), "expected first parent cell")
    local secondCell = assert(menu.panel:getCell(1, 2), "expected second parent cell")
    local fx, fy = cellCenter(firstCell)
    local sx, sy = cellCenter(secondCell)

    menu:mousemoved(fx, fy)
    expect(menu.childMenu).toBeTruthy()
    expect(menu.activeChildItem.text).toBe("Parent A")

    menu:mousemoved(sx, sy)
    expect(menu.childMenu).toBeTruthy()
    expect(menu.activeChildItem.text).toBe("Parent A")

    fakeNow = fakeNow + 0.10
    menu:update()
    expect(menu.childMenu).toBeTruthy()
    expect(menu.activeChildItem.text).toBe("Parent A")

    fakeNow = fakeNow + 0.10
    menu:update()
    expect(menu.childMenu).toBeTruthy()
    expect(menu.activeChildItem.text).toBe("Parent B")
  end)
end)
