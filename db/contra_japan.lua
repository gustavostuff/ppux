return {
  currentBank = 9,
  currentColor = 2,
  edits = {
    banks = {
    }
  },
  focusedWindowId = "ppu_frame_1",
  kind = "project",
  projectVersion = 1,
  romPatches = {
    [1] = {
      addresses = {
        from = 0x01C9CB,
        to = 0x01C9CC
      },
      reason = "Change ID cards BG table pointer",
      values = {
        [1] = 0x90,
        [2] = 0xAB
      }
    },
    [2] = {
      addresses = {
        from = 0x01C9C9,
        to = 0x01C9CA
      },
      reason = "Change Red falcon BG table pointer",
      values = {
        [1] = 0xA0,
        [2] = 0xAD
      }
    },
    [3] = {
      addresses = {
        from = 0x01C9C7,
        to = 0x01C9C8
      },
      reason = "Change meteorite BG table pointer",
      values = {
        [1] = 0xA0,
        [2] = 0xAC
      }
    }
  },
  skipOverwriteConfirm = false,
  syncDuplicateTiles = false,
  windowOrderIds = {
    [1] = "bank",
    [2] = "oam_jumping_animation",
    [3] = "oam_static_poses",
    [4] = "oam_animation_01",
    [5] = "static_art_1",
    [6] = "ppu_frame_1",
    [7] = "ppu_frame_3",
    [8] = "ppu_frame_2",
    [9] = "ppu_frame_5",
    [10] = "ppu_frame_4",
    [11] = "ppu_frame_6",
    [12] = "ppu_frame_7",
    [13] = "ppu_frame_8",
    [14] = "ppu_frame_9",
    [15] = "ppu_01",
    [16] = "palette_01",
    [17] = "palette_02",
    [18] = "rom_palette_1",
    [19] = "rom_palette_2",
    [20] = "rom_palette_5",
    [21] = "rom_palette_4",
    [22] = "rom_palette_3",
    [23] = "rom_palette_6",
    [24] = "rom_palette_7",
    [25] = "stage_01_sprites",
    [26] = "rom_palette_01",
    [27] = "rom_palette_02",
    [28] = "pattern_table_cutscene_1",
    [29] = "pattern_table_1",
    [30] = "pattern_table_3",
    [31] = "pattern_table_2",
    [32] = "pattern_table_4",
    [33] = "pattern_table_5",
    [34] = "pattern_table_6",
    [35] = "pattern_table_oam_running",
    [36] = "pattern_table_title_nametable",
    [37] = "pattern_table_title_sprites"
  },
  windows = {
    [1] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      currentBank = 9,
      id = "bank",
      kind = "chr",
      layers = {
        [1] = {
          items = {
          },
          name = "Bank 1",
          opacity = 1
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      orderMode = "normal",
      rows = 32,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Bank 9/16",
      visibleCols = 9,
      visibleRows = 32,
      x = 30,
      y = 30,
      z = 10,
      zoom = 1
    },
    [2] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 8,
      delaysPerLayer = {
        [1] = 0.2,
        [2] = 0.2
      },
      id = "oam_jumping_animation",
      kind = "oam_animation",
      layers = {
        [1] = {
          items = {
            [1] = { startAddr = 0x009648 },
            [2] = { startAddr = 0x00964C },
            [3] = { startAddr = 0x009644 },
            [4] = { startAddr = 0x009650 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 30,
          originY = 30,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x009655 },
            [2] = { startAddr = 0x009659 },
            [3] = { startAddr = 0x00965D }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 30,
          originY = 30,
          paletteData = {
            winId = "stage_01_sprites"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      multiRowToolbar = false,
      nonActiveLayerOpacity = 0,
      rows = 8,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = true,
      title = "OAM: Stage 1 jump",
      visibleCols = 4,
      visibleRows = 8,
      x = 110,
      y = 30,
      z = 20,
      zoom = 2
    },
    [3] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 8,
      delaysPerLayer = {
        [1] = 0.2,
        [2] = 0.2,
        [3] = 0.2
      },
      id = "oam_static_poses",
      kind = "oam_animation",
      layers = {
        [1] = {
          items = {
            [1] = { startAddr = 0x0096A5 },
            [2] = { startAddr = 0x0096A9 },
            [3] = { startAddr = 0x0096AD },
            [4] = { startAddr = 0x00961C },
            [5] = { startAddr = 0x009620 },
            [6] = { startAddr = 0x009624 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 30,
          originY = 35,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x00961C },
            [2] = { startAddr = 0x009620 },
            [3] = { startAddr = 0x009624 },
            [4] = { startAddr = 0x00971D },
            [5] = { startAddr = 0x009721 },
            [6] = { startAddr = 0x009719 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 3",
          opacity = 1,
          originX = 30,
          originY = 35,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [3] = {
          items = {
            [1] = { startAddr = 0x009729 },
            [2] = { startAddr = 0x00972D },
            [3] = { startAddr = 0x009731 },
            [4] = { startAddr = 0x009735 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 3",
          opacity = 1,
          originX = 30,
          originY = 35,
          paletteData = {
            winId = "stage_01_sprites"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      multiRowToolbar = false,
      nonActiveLayerOpacity = 0,
      rows = 9,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "OAM: Stage 1 poses",
      visibleCols = 4,
      visibleRows = 9,
      x = 110,
      y = 52,
      z = 30,
      zoom = 2
    },
    [4] = {
      activeLayer = 5,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 8,
      delaysPerLayer = {
        [1] = 0.15,
        [2] = 0.15,
        [3] = 0.15,
        [4] = 0.15,
        [5] = 0.15,
        [6] = 0.15
      },
      id = "oam_animation_01",
      kind = "oam_animation",
      layers = {
        [1] = {
          items = {
            [1] = { startAddr = 0x0095FA },
            [2] = { startAddr = 0x0095F6 },
            [3] = { startAddr = 0x0095F2 },
            [4] = { startAddr = 0x0095EA },
            [5] = { startAddr = 0x0095EE }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 30,
          originY = 30,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x009603 },
            [2] = { startAddr = 0x0095FF },
            [3] = { startAddr = 0x00960B },
            [4] = { startAddr = 0x009607 },
            [5] = { startAddr = 0x00960F }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 30,
          originY = 30,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [3] = {
          items = {
            [1] = { startAddr = 0x009624 },
            [2] = { startAddr = 0x00961C },
            [3] = { startAddr = 0x009620 },
            [4] = { startAddr = 0x009614 },
            [5] = { startAddr = 0x009618 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 3",
          opacity = 1,
          originX = 30,
          originY = 30,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [4] = {
          items = {
            [1] = { startAddr = 0x0095F2 },
            [2] = { startAddr = 0x0095FA },
            [3] = { startAddr = 0x0095F6 },
            [4] = { startAddr = 0x009629 },
            [5] = { startAddr = 0x00962D }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 4",
          opacity = 1,
          originX = 30,
          originY = 30,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [5] = {
          items = {
            [1] = { startAddr = 0x009607 },
            [2] = { startAddr = 0x00960B },
            [3] = { startAddr = 0x00960F },
            [4] = { startAddr = 0x0095FF },
            [5] = { startAddr = 0x009603 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 5",
          opacity = 1,
          originX = 30,
          originY = 30,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [6] = {
          items = {
            [1] = { startAddr = 0x009624 },
            [2] = { startAddr = 0x00961C },
            [3] = { startAddr = 0x009620 },
            [4] = { startAddr = 0x009635 },
            [5] = { startAddr = 0x009639 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_running",
          mode = "8x16",
          name = "Frame 6",
          opacity = 1,
          originX = 30,
          originY = 30,
          paletteData = {
            winId = "stage_01_sprites"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      multiRowToolbar = false,
      nonActiveLayerOpacity = 0,
      rows = 8,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "OAM: Stage 1 run",
      visibleCols = 4,
      visibleRows = 8,
      x = 110,
      y = 74,
      z = 40,
      zoom = 2
    },
    [5] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 8,
      id = "static_art_1",
      kind = "static_art",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 6, col = 2, row = 1, tile = 349 },
            [2] = { bank = 6, col = 3, row = 1, tile = 350 },
            [3] = { bank = 6, col = 4, row = 1, tile = 351 },
            [4] = { bank = 6, col = 2, row = 2, tile = 352 },
            [5] = { bank = 6, col = 3, row = 2, tile = 353 },
            [6] = { bank = 6, col = 4, row = 2, tile = 354 },
            [7] = { bank = 6, col = 5, row = 2, tile = 355 },
            [8] = { bank = 6, col = 2, row = 3, tile = 356 },
            [9] = { bank = 6, col = 3, row = 3, tile = 357 },
            [10] = { bank = 6, col = 4, row = 3, tile = 358 },
            [11] = { bank = 6, col = 5, row = 3, tile = 359 },
            [12] = { bank = 6, col = 2, row = 4, tile = 360 },
            [13] = { bank = 6, col = 3, row = 4, tile = 361 },
            [14] = { bank = 6, col = 4, row = 4, tile = 362 },
            [15] = { bank = 6, col = 3, row = 5, tile = 363 },
            [16] = { bank = 6, col = 4, row = 5, tile = 375 }
          },
          kind = "tile",
          name = "Layer 1",
          opacity = 1
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 7,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Static art: Cutscene 2 Lance face",
      visibleCols = 3,
      visibleRows = 7,
      x = 183,
      y = 30,
      z = 50,
      zoom = 3
    },
    [6] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 32,
      id = "ppu_frame_3",
      kind = "ppu_frame",
      layers = {
        [1] = {
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_cutscene_1",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x01255A,
          nametableStartAddr = 0x012493,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_4"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x00A2DE },
            [2] = { startAddr = 0x00A2E6 },
            [3] = { startAddr = 0x00A2EA },
            [4] = { startAddr = 0x00A2F2 },
            [5] = { startAddr = 0x00A2EE },
            [6] = { startAddr = 0x009B23 },
            [7] = { startAddr = 0x009B27 },
            [8] = { startAddr = 0x009B2B },
            [9] = { startAddr = 0x009B2F },
            [10] = { startAddr = 0x009B33 },
            [11] = { startAddr = 0x009B37 },
            [12] = { startAddr = 0x009B3B },
            [13] = { startAddr = 0x009B3F },
            [14] = { startAddr = 0x009B43 },
            [15] = { startAddr = 0x009B47 },
            [16] = { startAddr = 0x009B4B },
            [17] = { startAddr = 0x009B4F },
            [18] = { startAddr = 0x009B1F },
            [19] = { startAddr = 0x009B53 },
            [20] = { startAddr = 0x009B17 },
            [21] = { startAddr = 0x009B57 },
            [22] = { startAddr = 0x009C12 },
            [23] = { startAddr = 0x009C1A },
            [24] = { startAddr = 0x009B6E },
            [25] = { startAddr = 0x009B72 },
            [26] = { startAddr = 0x009B1B },
            [27] = { startAddr = 0x00A2E2 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_cutscene_1",
          mode = "8x16",
          name = "Sprites",
          opacity = 1,
          originX = 128,
          originY = 128,
          paletteData = {
            winId = "rom_palette_3"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "PPU: Cutscene 1 Lance",
      visibleCols = 2,
      visibleRows = 9,
      x = 263,
      y = 52,
      z = 60,
      zoom = 4
    },
    [7] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 32,
      id = "ppu_frame_2",
      kind = "ppu_frame",
      layers = {
        [1] = {
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_1",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x01268B,
          nametableStartAddr = 0x01255B,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_1"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x00A32E },
            [2] = { startAddr = 0x00A336 },
            [3] = { startAddr = 0x00A33A },
            [4] = { startAddr = 0x00A33E },
            [5] = { startAddr = 0x00A342 },
            [6] = { startAddr = 0x00A352 },
            [7] = { startAddr = 0x00A356 },
            [8] = { startAddr = 0x00A35E },
            [9] = { startAddr = 0x00A362 },
            [10] = { startAddr = 0x00A366 },
            [11] = { startAddr = 0x00A36A },
            [12] = { startAddr = 0x00A36E },
            [13] = { startAddr = 0x00A372 },
            [14] = { startAddr = 0x00A37A },
            [15] = { startAddr = 0x00A37E },
            [16] = { startAddr = 0x00A382 },
            [17] = { startAddr = 0x00A386 },
            [18] = { startAddr = 0x00A38A },
            [19] = { startAddr = 0x00A38E },
            [20] = { startAddr = 0x00A392 },
            [21] = { startAddr = 0x00A396 },
            [22] = { startAddr = 0x00A39A },
            [23] = { startAddr = 0x00A39E },
            [24] = { startAddr = 0x00A346 },
            [25] = { startAddr = 0x00A332 },
            [26] = { startAddr = 0x00A376 },
            [27] = { startAddr = 0x00A34E },
            [28] = { startAddr = 0x00A35A },
            [29] = { startAddr = 0x00A34A },
            [30] = { dy = 1, startAddr = 0x00A32A }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_2",
          mode = "8x16",
          name = "Sprites",
          opacity = 1,
          originX = 128,
          originY = 128,
          paletteData = {
            winId = "rom_palette_2"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = true,
      title = "PPU: Cutscene 2 Bill frame 1",
      visibleCols = 2,
      visibleRows = 9,
      x = 263,
      y = 74,
      z = 70,
      zoom = 4
    },
    [8] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 32,
      id = "ppu_frame_5",
      kind = "ppu_frame",
      layers = {
        [1] = {
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_3",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x01268B,
          nametableStartAddr = 0x01255B,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_1"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x00A37A },
            [2] = { startAddr = 0x00A37E },
            [3] = { startAddr = 0x00A382 },
            [4] = { startAddr = 0x00A386 },
            [5] = { startAddr = 0x00A38A },
            [6] = { startAddr = 0x00A38E },
            [7] = { startAddr = 0x00A392 },
            [8] = { startAddr = 0x00A396 },
            [9] = { startAddr = 0x00A39A },
            [10] = { startAddr = 0x00A39E },
            [11] = { startAddr = 0x00A3AB },
            [12] = { startAddr = 0x00A3AF },
            [13] = { startAddr = 0x00A3B3 },
            [14] = { startAddr = 0x00A3B7 },
            [15] = { startAddr = 0x00A3C3 },
            [16] = { startAddr = 0x00A3BB },
            [17] = { startAddr = 0x00A3A7 },
            [18] = { startAddr = 0x00A3CF },
            [19] = { startAddr = 0x00A3D7 },
            [20] = { startAddr = 0x00A3DB },
            [21] = { startAddr = 0x00A3DF },
            [22] = { startAddr = 0x00A3E3 },
            [23] = { startAddr = 0x00A3E7 },
            [24] = { startAddr = 0x00A3EB },
            [25] = { startAddr = 0x00A3CB },
            [26] = { startAddr = 0x00A3BF },
            [27] = { startAddr = 0x00A3C7 },
            [28] = { startAddr = 0x00A3EF },
            [29] = { startAddr = 0x00A46B },
            [30] = { startAddr = 0x00A46F },
            [31] = { startAddr = 0x00A3A3 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_2",
          mode = "8x16",
          name = "Sprites",
          opacity = 1,
          originX = 128,
          originY = 128,
          paletteData = {
            winId = "rom_palette_2"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = true,
      title = "PPU: Cutscene 2 Bill frame 2",
      visibleCols = 2,
      visibleRows = 10,
      x = 263,
      y = 96,
      z = 80,
      zoom = 4
    },
    [9] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 32,
      id = "ppu_frame_4",
      kind = "ppu_frame",
      layers = {
        [1] = {
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_1",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x01268B,
          nametableStartAddr = 0x01255B,
          noOverflowSupported = false,
          onTheFlyReplacements = {
            [1] = {
              col = 9,
              row = 7,
              tileIndex = 171
            },
            [2] = {
              col = 10,
              row = 7,
              tileIndex = 183
            },
            [3] = {
              col = 8,
              row = 6,
              tileIndex = 168
            },
            [4] = {
              col = 9,
              row = 6,
              tileIndex = 169
            },
            [5] = {
              col = 10,
              row = 6,
              tileIndex = 170
            },
            [6] = {
              col = 8,
              row = 5,
              tileIndex = 164
            },
            [7] = {
              col = 9,
              row = 5,
              tileIndex = 165
            },
            [8] = {
              col = 10,
              row = 5,
              tileIndex = 166
            },
            [9] = {
              col = 11,
              row = 5,
              tileIndex = 167
            },
            [10] = {
              col = 8,
              row = 4,
              tileIndex = 160
            },
            [11] = {
              col = 9,
              row = 4,
              tileIndex = 161
            },
            [12] = {
              col = 10,
              row = 4,
              tileIndex = 162
            },
            [13] = {
              col = 11,
              row = 4,
              tileIndex = 163
            },
            [14] = {
              col = 8,
              row = 3,
              tileIndex = 157
            },
            [15] = {
              col = 9,
              row = 3,
              tileIndex = 158
            },
            [16] = {
              col = 10,
              row = 3,
              tileIndex = 159
            }
          },
          opacity = 1,
          paletteData = {
            winId = "rom_palette_4"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x00A352 },
            [2] = { startAddr = 0x00A356 },
            [3] = { startAddr = 0x00A35E },
            [4] = { startAddr = 0x00A362 },
            [5] = { startAddr = 0x00A366 },
            [6] = { startAddr = 0x00A36A },
            [7] = { startAddr = 0x00A36E },
            [8] = { startAddr = 0x00A372 },
            [9] = { startAddr = 0x00A37A },
            [10] = { startAddr = 0x00A37E },
            [11] = { startAddr = 0x00A382 },
            [12] = { startAddr = 0x00A386 },
            [13] = { startAddr = 0x00A38A },
            [14] = { startAddr = 0x00A38E },
            [15] = { startAddr = 0x00A392 },
            [16] = { startAddr = 0x00A396 },
            [17] = { startAddr = 0x00A39A },
            [18] = { startAddr = 0x00A39E },
            [19] = { startAddr = 0x00A34A },
            [20] = { startAddr = 0x00A346 },
            [21] = { startAddr = 0x00A376 },
            [22] = { startAddr = 0x00A34E },
            [23] = { startAddr = 0x00A35A },
            [24] = { startAddr = 0x00A3FF },
            [25] = { startAddr = 0x00A403 },
            [26] = { startAddr = 0x00A407 },
            [27] = { startAddr = 0x00A40B },
            [28] = { startAddr = 0x00A40F },
            [29] = { startAddr = 0x00A413 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_2",
          mode = "8x16",
          name = "Sprites",
          opacity = 1,
          originX = 128,
          originY = 128,
          paletteData = {
            winId = "rom_palette_3"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "PPU: Cutscene 2 Lance frame 1",
      visibleCols = 2,
      visibleRows = 11,
      x = 263,
      y = 118,
      z = 90,
      zoom = 4
    },
    [10] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 32,
      id = "ppu_frame_6",
      kind = "ppu_frame",
      layers = {
        [1] = {
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_3",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x01268B,
          nametableStartAddr = 0x01255B,
          noOverflowSupported = false,
          onTheFlyReplacements = {
            [1] = {
              col = 9,
              row = 7,
              tileIndex = 171
            },
            [2] = {
              col = 10,
              row = 7,
              tileIndex = 183
            },
            [3] = {
              col = 8,
              row = 6,
              tileIndex = 168
            },
            [4] = {
              col = 9,
              row = 6,
              tileIndex = 169
            },
            [5] = {
              col = 10,
              row = 6,
              tileIndex = 170
            },
            [6] = {
              col = 8,
              row = 5,
              tileIndex = 164
            },
            [7] = {
              col = 9,
              row = 5,
              tileIndex = 165
            },
            [8] = {
              col = 10,
              row = 5,
              tileIndex = 166
            },
            [9] = {
              col = 11,
              row = 5,
              tileIndex = 167
            },
            [10] = {
              col = 8,
              row = 4,
              tileIndex = 160
            },
            [11] = {
              col = 9,
              row = 4,
              tileIndex = 161
            },
            [12] = {
              col = 10,
              row = 4,
              tileIndex = 162
            },
            [13] = {
              col = 11,
              row = 4,
              tileIndex = 163
            },
            [14] = {
              col = 8,
              row = 3,
              tileIndex = 157
            },
            [15] = {
              col = 9,
              row = 3,
              tileIndex = 158
            },
            [16] = {
              col = 10,
              row = 3,
              tileIndex = 159
            }
          },
          opacity = 1,
          paletteData = {
            winId = "rom_palette_4"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x00A37A },
            [2] = { startAddr = 0x00A37E },
            [3] = { startAddr = 0x00A382 },
            [4] = { startAddr = 0x00A386 },
            [5] = { startAddr = 0x00A38A },
            [6] = { startAddr = 0x00A38E },
            [7] = { startAddr = 0x00A392 },
            [8] = { startAddr = 0x00A396 },
            [9] = { startAddr = 0x00A39A },
            [10] = { startAddr = 0x00A39E },
            [11] = { startAddr = 0x00A3BF },
            [12] = { startAddr = 0x00A3C7 },
            [13] = { startAddr = 0x00A3D7 },
            [14] = { startAddr = 0x00A3DB },
            [15] = { startAddr = 0x00A3CF },
            [16] = { startAddr = 0x00A3D3 },
            [17] = { startAddr = 0x00A376 },
            [18] = { startAddr = 0x00A3DF },
            [19] = { startAddr = 0x00A3E3 },
            [20] = { startAddr = 0x00A3E7 },
            [21] = { startAddr = 0x00A3EB },
            [22] = { startAddr = 0x00A41B },
            [23] = { startAddr = 0x00A41F },
            [24] = { startAddr = 0x00A427 },
            [25] = { startAddr = 0x00A423 },
            [26] = { startAddr = 0x00A42B },
            [27] = { startAddr = 0x00A42F },
            [28] = { startAddr = 0x00A3C3 },
            [29] = { startAddr = 0x00A3CB },
            [30] = { startAddr = 0x00A46B },
            [31] = { startAddr = 0x00A46F }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_2",
          mode = "8x16",
          name = "Sprites",
          opacity = 1,
          originX = 128,
          originY = 128,
          paletteData = {
            winId = "rom_palette_3"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "PPU: Cutscene 2 Lance frame 2",
      visibleCols = 2,
      visibleRows = 9,
      x = 263,
      y = 140,
      z = 100,
      zoom = 4
    },
    [11] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "palette_01",
      items = {
        [1] = { code = "0C", col = 0, row = 0 },
        [2] = { code = "14", col = 1, row = 0 },
        [3] = { code = "24", col = 2, row = 0 },
        [4] = { code = "34", col = 3, row = 0 }
      },
      kind = "palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteName = "p1",
      rows = 1,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 0,
      selectedRow = 0,
      showGrid = "none",
      title = "Palette: Generic 1",
      visibleCols = 4,
      visibleRows = 1,
      x = 343,
      y = 30,
      z = 110,
      zoom = 1
    },
    [12] = {
      activePalette = true,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "palette_02",
      items = {
        [1] = { code = "0F", col = 0, row = 0 },
        [2] = { code = "27", col = 1, row = 0 },
        [3] = { code = "17", col = 2, row = 0 },
        [4] = { code = "07", col = 3, row = 0 }
      },
      kind = "palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteName = "p2",
      rows = 1,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 2,
      selectedRow = 0,
      showGrid = "none",
      title = "Palette: Generic 2",
      visibleCols = 4,
      visibleRows = 1,
      x = 343,
      y = 52,
      z = 120,
      zoom = 1
    },
    [13] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_1",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = false,
            [2] = 0x01D25E,
            [3] = 0x01D25F,
            [4] = 0x01D260
          },
          [2] = {
            [1] = false,
            [2] = 0x01D261,
            [3] = 0x01D262,
            [4] = 0x01D263
          },
          [3] = {
            [1] = false,
            [2] = 0x01D264,
            [3] = 0x01D265,
            [4] = 0x01D266
          },
          [4] = {
            [1] = false,
            [2] = 0x01D267,
            [3] = 0x01D268,
            [4] = 0x01D269
          }
        },
        userDefinedCode = "0F,2,0;21,3,0"
      },
      paletteName = "smooth_fbx",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 2,
      selectedRow = 2,
      showGrid = "chess",
      title = "ROM pal: Bill BG",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 30,
      z = 130,
      zoom = 1
    },
    [14] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_2",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = false,
            [2] = 0x01D26A,
            [3] = 0x01D26B,
            [4] = 0x01D26C
          },
          [2] = {
            [1] = false,
            [2] = 0x01D26D,
            [3] = 0x01D26E,
            [4] = 0x01D26F
          },
          [3] = {
            [1] = false,
            [2] = 0x01D270,
            [3] = 0x01D271,
            [4] = 0x01D272
          },
          [4] = {
            [1] = false,
            [2] = 0x01D273,
            [3] = 0x01D274,
            [4] = 0x01D275
          }
        },
        userDefinedCode = "02,3,1"
      },
      paletteName = "smooth_fbx",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 1,
      showGrid = "chess",
      title = "ROM pal: Bill sprites",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 52,
      z = 140,
      zoom = 1
    },
    [15] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_5",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = false,
            [2] = 0x01D258,
            [3] = 0x01D259,
            [4] = 0x01D25A
          },
          [2] = {
            [1] = false,
            [2] = 0x01D25B,
            [3] = 0x01D25C,
            [4] = 0x01D25D
          },
          [3] = {
            [1] = false,
            [2] = 0x01D249,
            [3] = 0x01D24A,
            [4] = 0x01D24B
          },
          [4] = {
            [1] = false,
            [2] = 0x01D24C,
            [3] = 0x01D24D,
            [4] = 0x01D24E
          }
        }
      },
      paletteName = "smooth_fbx",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 3,
      showGrid = "chess",
      title = "ROM pal: ID cards",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 74,
      z = 150,
      zoom = 1
    },
    [16] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_4",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = false,
            [2] = 0x01D25E,
            [3] = 0x01D25F,
            [4] = 0x01D260
          },
          [2] = {
            [1] = false,
            [2] = 0x01D261,
            [3] = 0x01D262,
            [4] = 0x01D263
          },
          [3] = {
            [1] = false,
            [2] = 0x01D279,
            [3] = 0x01D27A,
            [4] = 0x01D27B
          },
          [4] = {
            [1] = false,
            [2] = 0x01D267,
            [3] = 0x01D268,
            [4] = 0x01D269
          }
        },
        userDefinedCode = "0F,2,0;21,3,0"
      },
      paletteName = "smooth_fbx",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 0,
      showGrid = "chess",
      title = "ROM pal: Lance BG",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 96,
      z = 160,
      zoom = 1
    },
    [17] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_3",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = false,
            [2] = 0x01D26A,
            [3] = 0x01D26B,
            [4] = 0x01D26C
          },
          [2] = {
            [1] = false,
            [2] = 0x01D26D,
            [3] = 0x01D26E,
            [4] = 0x01D26F
          },
          [3] = {
            [1] = false,
            [2] = 0x01D276,
            [3] = 0x01D277,
            [4] = 0x01D278
          },
          [4] = {
            [1] = false,
            [2] = 0x01D273,
            [3] = 0x01D274,
            [4] = 0x01D275
          }
        },
        userDefinedCode = "02,3,1"
      },
      paletteName = "smooth_fbx",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 2,
      selectedRow = 0,
      showGrid = "chess",
      title = "ROM pal: Lance sprites",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 118,
      z = 170,
      zoom = 1
    },
    [18] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_6",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = false,
            [2] = 0x01D243,
            [3] = 0x01D244,
            [4] = 0x01D245
          },
          [2] = {
            [1] = false,
            [2] = 0x01D246,
            [3] = 0x01D247,
            [4] = 0x01D248
          },
          [3] = {
            [1] = false,
            [2] = 0x01D249,
            [3] = 0x01D24A,
            [4] = 0x01D24B
          },
          [4] = {
            [1] = false,
            [2] = 0x01D24C,
            [3] = 0x01D24D,
            [4] = 0x01D24E
          }
        }
      },
      paletteName = "smooth_fbx",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 3,
      showGrid = "chess",
      title = "ROM pal: Meteorite",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 140,
      z = 180,
      zoom = 1
    },
    [19] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_7",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = false,
            [2] = 0x01D252,
            [3] = 0x01D253,
            [4] = 0x01D254
          },
          [2] = {
            [1] = false,
            [2] = 0x01D255,
            [3] = 0x01D256,
            [4] = 0x01D257
          },
          [3] = {
            [1] = false,
            [2] = 0x01D249,
            [3] = 0x01D24A,
            [4] = 0x01D24B
          },
          [4] = {
            [1] = false,
            [2] = 0x01D24C,
            [3] = 0x01D24D,
            [4] = 0x01D24E
          }
        }
      },
      paletteName = "smooth_fbx",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 1,
      showGrid = "chess",
      title = "ROM Pal: Red falcon",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 162,
      z = 190,
      zoom = 1
    },
    [20] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "stage_01_sprites",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = false,
            [2] = 0x01D0F3,
            [3] = 0x01D0F4,
            [4] = 0x01D0F5
          },
          [2] = {
            [1] = false,
            [2] = 0x01D0F6,
            [3] = 0x01D0F7,
            [4] = 0x01D0F8
          },
          [3] = {
            [1] = false,
            [2] = 0x01D27C,
            [3] = 0x01D27D,
            [4] = 0x01D27E
          },
          [4] = {
            [1] = false,
            [2] = 0x01D108,
            [3] = 0x01D109,
            [4] = 0x01D10A
          }
        }
      },
      paletteName = "stage_01_sprites",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 0,
      showGrid = "lines",
      title = "ROM pal: Stage 1 sprites",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 184,
      z = 200,
      zoom = 1
    },
    [21] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_01",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = 0x01F688,
            [2] = 0x01F679,
            [3] = 0x01F67A,
            [4] = 0x01F67B
          },
          [2] = {
            [1] = 0x01F688,
            [2] = 0x01F67D,
            [3] = 0x01F67E,
            [4] = 0x01F67F
          },
          [3] = {
            [1] = 0x01F688,
            [2] = 0x01F681,
            [3] = 0x01F682,
            [4] = 0x01F683
          },
          [4] = {
            [1] = 0x01F688,
            [2] = 0x01F685,
            [3] = 0x01F686,
            [4] = 0x01F687
          }
        }
      },
      paletteName = "title_palettes",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 0,
      selectedRow = 0,
      showGrid = "none",
      title = "ROM pal: Title BG",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 206,
      z = 210,
      zoom = 1
    },
    [22] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_02",
      kind = "rom_palette",
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteData = {
        romColors = {
          [1] = {
            [1] = 0x01F688,
            [2] = 0x01F689,
            [3] = 0x01F68A,
            [4] = 0x01F68B
          },
          [2] = {
            [1] = 0x01F688,
            [2] = 0x01F68D,
            [3] = 0x01F68E,
            [4] = 0x01F68F
          },
          [3] = {
            [1] = 0x01F688,
            [2] = 0x01F691,
            [3] = 0x01F692,
            [4] = 0x01F693
          },
          [4] = {
            [1] = 0x01F688,
            [2] = 0x01F695,
            [3] = 0x01F696,
            [4] = 0x01F697
          }
        }
      },
      paletteName = "title_screen_sprite_palettes",
      paletteRole = "rom",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 1,
      selectedRow = 1,
      showGrid = "none",
      title = "ROM pal: Title sprites",
      visibleCols = 4,
      visibleRows = 4,
      x = 448,
      y = 228,
      z = 220,
      zoom = 1
    },
    [23] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_cutscene_1",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 16,
                from = 128,
                to = 191
              },
              [2] = {
                bank = 6,
                from = 64,
                to = 255
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "PT: Cutscene 1",
      visibleCols = 3,
      visibleRows = 16,
      x = 552,
      y = 30,
      z = 230,
      zoom = 3
    },
    [24] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_1",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 16,
                from = 128,
                to = 191
              },
              [2] = {
                bank = 6,
                from = 256,
                to = 447
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "none",
      title = "PT: Cutscene 2 BG frame 1",
      visibleCols = 3,
      visibleRows = 16,
      x = 552,
      y = 52,
      z = 240,
      zoom = 3
    },
    [25] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_3",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 16,
                from = 128,
                to = 191
              },
              [2] = {
                bank = 6,
                from = 448,
                to = 511
              },
              [3] = {
                bank = 7,
                from = 0,
                to = 63
              },
              [4] = {
                bank = 6,
                from = 384,
                to = 447
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "PT: Cutscene 2 BG frame 2",
      visibleCols = 3,
      visibleRows = 16,
      x = 552,
      y = 74,
      z = 250,
      zoom = 3
    },
    [26] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_2",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x16",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 7,
                from = 64,
                to = 127
              },
              [2] = {
                bank = 7,
                from = 192,
                to = 255
              },
              [3] = {
                bank = 7,
                from = 64,
                to = 127
              },
              [4] = {
                bank = 7,
                from = 64,
                to = 127
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "PT: Cutscene 2 sprites",
      visibleCols = 3,
      visibleRows = 16,
      x = 552,
      y = 96,
      z = 260,
      zoom = 3
    },
    [27] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_4",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 16,
                from = 128,
                to = 191
              },
              [2] = {
                bank = 16,
                from = 448,
                to = 511
              },
              [3] = {
                bank = 16,
                from = 384,
                to = 447
              },
              [4] = {
                bank = 9,
                from = 192,
                to = 255
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "PT: ID cards",
      visibleCols = 3,
      visibleRows = 16,
      x = 552,
      y = 118,
      z = 270,
      zoom = 3
    },
    [28] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_5",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 16,
                from = 128,
                to = 191
              },
              [2] = {
                bank = 16,
                from = 192,
                to = 255
              },
              [3] = {
                bank = 16,
                from = 256,
                to = 319
              },
              [4] = {
                bank = 9,
                from = 192,
                to = 255
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "PT: meteorite scene",
      visibleCols = 10,
      visibleRows = 16,
      x = 552,
      y = 140,
      z = 280,
      zoom = 1
    },
    [29] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_6",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 16,
                from = 128,
                to = 191
              },
              [2] = {
                bank = 16,
                from = 320,
                to = 447
              },
              [3] = {
                bank = 9,
                from = 192,
                to = 255
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "PT: Red falcon",
      visibleCols = 10,
      visibleRows = 16,
      x = 552,
      y = 162,
      z = 290,
      zoom = 1
    },
    [30] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_oam_running",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x16",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 1,
                from = 64,
                to = 127
              },
              [2] = {
                bank = 1,
                from = 256,
                to = 319
              },
              [3] = {
                bank = 1,
                from = 384,
                to = 511
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "PT: Stage 1 sprites",
      visibleCols = 3,
      visibleRows = 16,
      x = 552,
      y = 184,
      z = 300,
      zoom = 3
    },
    [31] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_title_nametable",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x8",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 9,
                from = 0,
                to = 255
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "PT: Title BG",
      visibleCols = 3,
      visibleRows = 16,
      x = 552,
      y = 206,
      z = 310,
      zoom = 3
    },
    [32] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = true,
      cols = 16,
      id = "pattern_table_title_sprites",
      kind = "pattern_table",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          mode = "8x16",
          name = "Pattern table",
          opacity = 1,
          patternTable = {
            ranges = {
              [1] = {
                bank = 4,
                from = 0,
                to = 255
              }
            }
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "PT: Title sprites",
      visibleCols = 3,
      visibleRows = 16,
      x = 552,
      y = 228,
      z = 320,
      zoom = 3
    },
    [33] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 32,
      id = "ppu_frame_8",
      kind = "ppu_frame",
      layers = {
        [1] = {
          attrMode = false,
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_5",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x011A71,
          nametableStartAddr = 0x0119F0,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_6"
          },
          relocateTo = 0x012CB0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 11,
      scrollRow = 6,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "PPU: Meteorite scene",
      visibleCols = 10,
      visibleRows = 9,
      x = 24,
      y = 115,
      z = 330,
      zoom = 1
    },
    [34] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 32,
      id = "ppu_01",
      kind = "ppu_frame",
      layers = {
        [1] = {
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_title_nametable",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x010160,
          nametableStartAddr = 0x010011,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_01"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x009F2B },
            [2] = { startAddr = 0x009F57 },
            [3] = { startAddr = 0x009F43 },
            [4] = { startAddr = 0x009F03 },
            [5] = { startAddr = 0x009F3B },
            [6] = { startAddr = 0x009F3F },
            [7] = { startAddr = 0x009F33 },
            [8] = { startAddr = 0x009F37 },
            [9] = { startAddr = 0x009F13 },
            [10] = { startAddr = 0x009F47 },
            [11] = { startAddr = 0x009F27 },
            [12] = { startAddr = 0x009F0F },
            [13] = { startAddr = 0x009F1F },
            [14] = { startAddr = 0x009F17 },
            [15] = { startAddr = 0x009F0B },
            [16] = { startAddr = 0x009F1B },
            [17] = { startAddr = 0x009F07 },
            [18] = { startAddr = 0x009F4F },
            [19] = { startAddr = 0x009F2F },
            [20] = { startAddr = 0x009F4B },
            [21] = { startAddr = 0x009F23 },
            [22] = { startAddr = 0x009F53 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_title_sprites",
          mode = "8x16",
          name = "Sprites",
          opacity = 1,
          originX = 179,
          originY = 120,
          paletteData = {
            winId = "rom_palette_02"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 0.8,
      rows = 30,
      scrollCol = 18,
      scrollRow = 14,
      showGrid = "chess",
      showSpriteOriginGuides = true,
      title = "PPU: Title",
      visibleCols = 9,
      visibleRows = 9,
      x = 26,
      y = 224,
      z = 340,
      zoom = 1
    },
    [35] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 32,
      id = "ppu_frame_9",
      kind = "ppu_frame",
      layers = {
        [1] = {
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_6",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x011AE5,
          nametableStartAddr = 0x011A72,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_7"
          },
          relocateTo = 0x012DB0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 6,
      scrollRow = 3,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "PPU: Red falcon",
      visibleCols = 15,
      visibleRows = 10,
      x = 130,
      y = 116,
      z = 350,
      zoom = 1
    },
    [36] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 32,
      id = "ppu_frame_7",
      kind = "ppu_frame",
      layers = {
        [1] = {
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_4",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x011BC1,
          nametableStartAddr = 0x011AE6,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_5"
          },
          relocateTo = 0x012BA0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 2,
      scrollRow = 2,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "PPU: ID cards",
      visibleCols = 30,
      visibleRows = 11,
      x = 119,
      y = 226,
      z = 360,
      zoom = 1
    },
    [37] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 32,
      id = "ppu_frame_1",
      kind = "ppu_frame",
      layers = {
        [1] = {
          codec = "konami",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_cutscene_1",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x01255A,
          nametableStartAddr = 0x012493,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_1"
          }
        },
        [2] = {
          items = {
            [1] = { startAddr = 0x009B0B },
            [2] = { startAddr = 0x009B13 },
            [3] = { startAddr = 0x009B23 },
            [4] = { startAddr = 0x009B27 },
            [5] = { startAddr = 0x009B2B },
            [6] = { startAddr = 0x009B2F },
            [7] = { startAddr = 0x009B33 },
            [8] = { startAddr = 0x009B37 },
            [9] = { startAddr = 0x009B3B },
            [10] = { startAddr = 0x009B3F },
            [11] = { startAddr = 0x009B43 },
            [12] = { startAddr = 0x009B47 },
            [13] = { startAddr = 0x009B4B },
            [14] = { startAddr = 0x009B4F },
            [15] = { startAddr = 0x009B1F },
            [16] = { startAddr = 0x009B53 },
            [17] = { startAddr = 0x009B17 },
            [18] = { startAddr = 0x009B57 },
            [19] = { startAddr = 0x009C12 },
            [20] = { startAddr = 0x009C1A },
            [21] = { startAddr = 0x009B6E },
            [22] = { startAddr = 0x009B72 },
            [23] = { startAddr = 0x009B1B },
            [24] = { startAddr = 0x009B07 },
            [25] = { startAddr = 0x009B0F },
            [26] = { startAddr = 0x009B03 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_cutscene_1",
          mode = "8x16",
          name = "Sprites",
          opacity = 1,
          originX = 128,
          originY = 128,
          paletteData = {
            winId = "rom_palette_2"
          }
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 0,
      scrollRow = 6,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "PPU: Cutscene 1 Bill",
      visibleCols = 18,
      visibleRows = 14,
      x = 345,
      y = 89,
      z = 370,
      zoom = 1
    }
  }
}
