-- TEMP / merge reference derived from contra_bikini_edition/base.lua windows section.
-- Not loaded by the project; copy entries into layout `windows = { ... }` as needed.
--
-- Intended wiring after pattern_table windows exist in the WM:
--   * PPU nametable tile layer (`kind = "tile"` with nametable addrs): set `linkedPatternTableWindowId`
--     plus keep or drop inline `patternTable` (resolve pass overwrites `.patternTable`
--     with the linked window's shared table when the id matches).
--   * PPU / OAM `sprite` layers: same field; add `patternTable` in the sketch window,
--     then link — CHR drops validate against the shared table when ranges are configured.
--
-- Window indices in the original file (for orientation only): 
--   [15] id=ppu_01 kind=ppu_frame — Layer 1 tile (nametable), Layer 2 sprites
--   [16] id=ppu_frame_1 kind=ppu_frame — Layer 1 tile, Layer 2 sprites  
--   [9] id=oam_static_poses kind=oam_animation — Frames 1–5 sprite layers
--   [14] id=oam_animation_01 kind=oam_animation — Frames 1–6 sprite layers

return {
  new_windows = {
    pattern_table_title_nametable = {
      kind = "pattern_table",
      id = "pattern_table_title_nametable",
      title = "Pattern — Title BG (linked ppu_01 L1)",
      x = 30,
      y = 200,
      z = 200,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      activeLayer = 1,
      visibleCols = 16,
      visibleRows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      collapsed = false,
      minimized = false,
      layers = {
        [1] = {
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          patternTable = {
            ranges = {
              [1] = {
                bank = 9,
                page = 1,
                tileRange = { from = 0, to = 255 },
              },
            },
          },
          items = {},
        },
      },
    },
    pattern_table_title_sprites = {
      kind = "pattern_table",
      id = "pattern_table_title_sprites",
      title = "Pattern — Title sprites (ppu_01 L2 sketch)",
      x = 30,
      y = 340,
      z = 205,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      activeLayer = 1,
      visibleCols = 16,
      visibleRows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      collapsed = false,
      minimized = false,
      layers = {
        [1] = {
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          -- Author ranges that cover sprite CHR (base uses bank 4 on title sprites).
          patternTable = { ranges = {} },
          items = {},
        },
      },
    },
    pattern_table_cutscene_nametable = {
      kind = "pattern_table",
      id = "pattern_table_cutscene_nametable",
      title = "Pattern — Cutscene BG (linked ppu_frame_1 L1)",
      x = 200,
      y = 200,
      z = 210,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      activeLayer = 1,
      visibleCols = 16,
      visibleRows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      collapsed = false,
      minimized = false,
      layers = {
        [1] = {
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          patternTable = {
            ranges = {
              [1] = {
                bank = 16,
                page = 1,
                tileRange = { from = 128, to = 191 },
              },
              [2] = {
                bank = 6,
                page = 1,
                tileRange = { from = 64, to = 255 },
              },
            },
          },
          items = {},
        },
      },
    },
    pattern_table_cutscene_sprites = {
      kind = "pattern_table",
      id = "pattern_table_cutscene_sprites",
      title = "Pattern — Cutscene sprites (ppu_frame_1 L2)",
      x = 200,
      y = 340,
      z = 215,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      activeLayer = 1,
      visibleCols = 16,
      visibleRows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      collapsed = false,
      minimized = false,
      layers = {
        [1] = {
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          patternTable = { ranges = {} },
          items = {},
        },
      },
    },
    pattern_table_oam_static = {
      kind = "pattern_table",
      id = "pattern_table_oam_static",
      title = "Pattern — OAM static poses",
      x = 380,
      y = 200,
      z = 220,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      activeLayer = 1,
      layers = {
        [1] = {
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          patternTable = { ranges = {} },
          items = {},
        },
      },
    },
    pattern_table_oam_run = {
      kind = "pattern_table",
      id = "pattern_table_oam_run",
      title = "Pattern — OAM running",
      x = 380,
      y = 340,
      z = 225,
      cellW = 8,
      cellH = 8,
      cols = 16,
      rows = 16,
      zoom = 2,
      activeLayer = 1,
      layers = {
        [1] = {
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          patternTable = { ranges = {} },
          items = {},
        },
      },
    },
  },

  -- Apply inside existing window entries (`windows[i].layers[j]`):
  layer_patch_examples = {

    ["ppu_01.layers[1].nametable.tile"] = {
      linkedPatternTableWindowId = "pattern_table_title_nametable",
    },
    ["ppu_01.layers[2].sprite"] = {
      linkedPatternTableWindowId = "pattern_table_title_sprites",
    },

    ["ppu_frame_1.layers[1].nametable.tile"] = {
      linkedPatternTableWindowId = "pattern_table_cutscene_nametable",
    },
    ["ppu_frame_1.layers[2].sprite"] = {
      linkedPatternTableWindowId = "pattern_table_cutscene_sprites",
    },

    -- OAM: each frame layer is sprite — link all frames that should share one logical table,
    -- or split into multiple pattern_table windows per animation.
    ["oam_static_poses.frames"] = {
      linkedPatternTableWindowId = "pattern_table_oam_static",
      -- set on layers[1] through layers[5] in the saved layout:
      per_layer_note = 'layers[k].linkedPatternTableWindowId = "pattern_table_oam_static"',
    },
    ["oam_animation_01.frames"] = {
      linkedPatternTableWindowId = "pattern_table_oam_run",
      per_layer_note = 'layers[k].linkedPatternTableWindowId = "pattern_table_oam_run"',
    },
  },
}
