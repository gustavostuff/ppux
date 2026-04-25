-- Merges scenario builder modules under builders/.
local function merge(dst, src)
  for k, v in pairs(src) do
    dst[k] = v
  end
end

local scenarios = {}
merge(scenarios, require("test.e2e_visible.scenarios.builders.context_menus"))
merge(scenarios, require("test.e2e_visible.scenarios.builders.modals_tile"))
merge(scenarios, require("test.e2e_visible.scenarios.builders.brush_palette_static"))
merge(scenarios, require("test.e2e_visible.scenarios.builders.undo_palette_rom"))
merge(scenarios, require("test.e2e_visible.scenarios.builders.save_modal_nav"))
merge(scenarios, require("test.e2e_visible.scenarios.builders.clipboard_matrix"))
merge(scenarios, require("test.e2e_visible.scenarios.builders.ppu_toolbar"))
merge(scenarios, require("test.e2e_visible.scenarios.builders.clipboard_paths"))
merge(scenarios, require("test.e2e_visible.scenarios.builders.grid_resize"))

return {
  scenarios = scenarios,
  aliases = require("test.e2e_visible.scenarios.scenario_aliases"),
}
