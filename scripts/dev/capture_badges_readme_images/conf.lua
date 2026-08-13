function love.conf(t)
  t.identity = "ppux-badge-capture"
  t.version = "11.5"
  t.console = false
  t.window.title = "PPUX badge capture"
  t.window.width = 128
  t.window.height = 48
  t.window.resizable = false
  t.window.vsync = 0
  t.window.msaa = 0
  t.window.highdpi = false
  t.modules.audio = false
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.touch = false
  t.modules.video = false
end
