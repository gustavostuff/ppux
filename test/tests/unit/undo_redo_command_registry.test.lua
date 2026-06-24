local Registry = require("controllers.input_support.undo_redo_command_registry")

describe("undo_redo_command_registry.lua", function()
  it("describes known event types", function()
    expect(Registry.describeEvent({ type = "paint" })).toBe("Paint")
    expect(Registry.describeEvent({ type = "tile_drag", mode = "copy" })).toBe("Tile copy")
    expect(Registry.describeEvent({ type = "composite", events = { {}, {} } })).toBe("Composite (2 actions)")
    expect(Registry.describeEvent({ type = "window_close" })).toBe("Close window")
  end)

  it("falls back for unknown types", function()
    expect(Registry.describeEvent({ type = "future_thing" })).toBe("future_thing")
    expect(Registry.describeEvent(nil)).toBe("Edit")
  end)

  it("registers apply handlers for window rename", function()
    local win = { title = "After" }
    expect(Registry.applyEvent({
      type = "window_rename",
      win = win,
      beforeTitle = "Before",
      afterTitle = "After",
    }, "undo", nil)).toBe(true)
    expect(win.title).toBe("Before")
  end)

  it("applyComposite delegates children in undo order", function()
    local order = {}
    local event = {
      type = "composite",
      events = {
        { type = "a" },
        { type = "b" },
        { type = "c" },
      },
    }
    local function applyChild(child)
      order[#order + 1] = child.type
      return true
    end
    expect(Registry.applyComposite(event, "undo", nil, applyChild)).toBe(true)
    expect(order).toEqual({ "c", "b", "a" })
    order = {}
    expect(Registry.applyComposite(event, "redo", nil, applyChild)).toBe(true)
    expect(order).toEqual({ "a", "b", "c" })
  end)

  it("exposes COMMANDS for every supported type", function()
    local expected = {
      "paint",
      "composite",
      "remove_tile",
      "tile_drag",
      "sprite_drag",
      "sprite_layer_origin",
      "palette_color",
      "window_rename",
      "rom_palette_address",
      "palette_link",
      "pattern_table_link",
      "window_create",
      "ppu_frame_range",
      "pattern_table_append",
      "animation_window_state",
      "grid_layout",
      "chr_tile_revert",
      "window_minimize_batch",
      "window_minimize_all",
      "window_restore_minimized_all",
      "window_collapse_all",
      "window_expand_all",
      "window_minimize",
      "window_close",
    }
    for _, typeName in ipairs(expected) do
      expect(Registry.COMMANDS[typeName]).toBeTruthy()
      expect(Registry.COMMANDS[typeName].describe).toBeTruthy()
    end
  end)
end)
