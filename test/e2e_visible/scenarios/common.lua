-- Shared step / point bindings for visible E2E scenario builders.

local BubbleExample = require("test.e2e_bubble_example")
local Steps = require("test.e2e_visible.steps")
local Points = require("test.e2e_visible.points")

local M = {}
M.BubbleExample = BubbleExample
M.Steps = Steps
M.Points = Points
M.PaletteLinkController = require("controllers.palette.palette_link_controller")
M.ContextualMenuController = require("controllers.ui.contextual_menu_controller")
M.images = require("images")

M.normalizeSpeedMultiplier = Steps.normalizeSpeedMultiplier
M.pause = Steps.pause
M.moveTo = Steps.moveTo
M.mouseDown = Steps.mouseDown
M.mouseUp = Steps.mouseUp
M.keyPress = Steps.keyPress
M.textInput = Steps.textInput
M.call = Steps.call
M.assertDelay = Steps.assertDelay
M.appendClick = Steps.appendClick
M.appendDrag = Steps.appendDrag

M.newWindowOptionCenter = Points.newWindowOptionCenter
M.newWindowOptionCenterByText = Points.newWindowOptionCenterByText
M.newWindowModeToggleCenter = Points.newWindowModeToggleCenter
M.textFieldDemoFieldCenter = Points.textFieldDemoFieldCenter
M.textFieldDemoFieldTextPoint = Points.textFieldDemoFieldTextPoint
M.spriteItemCenter = Points.spriteItemCenter
M.toolbarLinkHandleCenter = Points.toolbarLinkHandleCenter
M.windowHeaderCenter = Points.windowHeaderCenter
M.saveOptionCenter = Points.saveOptionCenter
M.menuRowCenter = Points.menuRowCenter
M.taskbarRootMenu = Points.taskbarRootMenu
M.childMenuRowCenter = Points.childMenuRowCenter
M.rootMenuItemCenter = Points.rootMenuItemCenter
M.resizeHandleCenter = Points.resizeHandleCenter
M.taskbarMenuGapPoint = Points.taskbarMenuGapPoint
M.assertTaskbarChildState = Points.assertTaskbarChildState

return M
