return {
  currentBank = 16,
  currentColor = 0,
  edits = {
    banks = {
    }
  },
  focusedWindowId = "ppu_01",
  kind = "project",
  projectVersion = 1,
  syncDuplicateTiles = false,
  windowOrderIds = {
    [1] = "bank",
    [2] = "oam_jumping_animation",
    [3] = "oam_animation_01",
    [4] = "oam_static_poses",
    [5] = "ppu_frame_1",
    [6] = "ppu_frame_3",
    [7] = "ppu_01",
    [8] = "palette_01",
    [9] = "palette_02",
    [10] = "rom_palette_1",
    [11] = "rom_palette_4",
    [12] = "rom_palette_2",
    [13] = "rom_palette_3",
    [14] = "stage_01_sprites",
    [15] = "rom_palette_01",
    [16] = "rom_palette_02",
    [17] = "pattern_table_cutscene_1",
    [18] = "pattern_table_oam_jumping",
    [19] = "pattern_table_oam_running",
    [20] = "pattern_table_oam_static_poses",
    [21] = "pattern_table_title_nametable",
    [22] = "pattern_table_title_sprites",
    [23] = "static_art_1"
  },
  windows = {
    [1] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
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
      minimized = true,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Pattern table - Title screen sprites",
      visibleCols = 16,
      visibleRows = 16,
      x = 179,
      y = 131,
      z = 10,
      zoom = 1
    },
    [2] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_4",
      kind = "rom_palette",
      minimized = true,
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
        userDefinedCode = "20,1,0;20,2,0;0F,3,0;27,1,1;17,2,1;07,3,1;14,1,2;04,2,2;17,3,2;2C,1,3;09,2,3;06,3,3"
      },
      paletteName = "smooth_fbx",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 2,
      showGrid = "chess",
      title = "BG cutscene 1 - Lance",
      visibleCols = 4,
      visibleRows = 4,
      x = 529,
      y = 255,
      z = 20,
      zoom = 1
    },
    [3] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = false,
      cols = 4,
      compactView = true,
      id = "rom_palette_3",
      kind = "rom_palette",
      minimized = true,
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
        userDefinedCode = "27,1,0;17,2,0;06,3,0;32,1,1;1C,2,1;02,3,1;20,1,2;1B,2,2;0C,3,2;10,1,3;00,2,3;02,3,3"
      },
      paletteName = "smooth_fbx",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 2,
      selectedRow = 0,
      showGrid = "chess",
      title = "Sprites cutscene 1 - Lance",
      visibleCols = 4,
      visibleRows = 4,
      x = 383,
      y = 231,
      z = 30,
      zoom = 1
    },
    [4] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "stage_01_sprites",
      kind = "rom_palette",
      minimized = true,
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
        },
        userDefinedCode = "37,1,0;12,2,0;0F,3,0;36,1,1;16,2,1;0F,3,1;20,1,2;26,2,2;16,3,2;20,1,3;00,2,3;0F,3,3"
      },
      paletteName = "stage_01_sprites",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 0,
      showGrid = "lines",
      title = "Stage 01 sprites",
      visibleCols = 4,
      visibleRows = 4,
      x = 531,
      y = 206,
      z = 40,
      zoom = 1
    },
    [5] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_01",
      kind = "rom_palette",
      minimized = true,
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
        },
        userDefinedCode = "0F,0,0;30,1,0;28,2,0;16,3,0;0F,0,1;30,1,1;06,2,1;16,3,1;0F,0,2;10,1,2;28,2,2;16,3,2;0F,0,3;30,1,3;36,2,3;26,3,3"
      },
      paletteName = "title_palettes",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 0,
      selectedRow = 0,
      showGrid = "none",
      title = "Title BG palettes",
      visibleCols = 4,
      visibleRows = 4,
      x = 537,
      y = 298,
      z = 50,
      zoom = 1
    },
    [6] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_02",
      kind = "rom_palette",
      minimized = true,
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
        },
        userDefinedCode = "0F,0,0;30,1,0;10,2,0;00,3,0;0F,0,1;30,1,1;38,2,1;28,3,1;0F,0,2;2C,1,2;1C,2,2;0C,3,2;0F,0,3;00,1,3;00,2,3;00,3,3"
      },
      paletteName = "title_screen_sprite_palettes",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 1,
      selectedRow = 1,
      showGrid = "none",
      title = "Title screen sprite palettes",
      visibleCols = 4,
      visibleRows = 4,
      x = 536,
      y = 277,
      z = 60,
      zoom = 1
    },
    [7] = {
      activePalette = false,
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
      minimized = true,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteName = "p2",
      rows = 1,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 0,
      showGrid = "none",
      title = "Global palette 2",
      visibleCols = 4,
      visibleRows = 1,
      x = 531,
      y = 159,
      z = 70,
      zoom = 1
    },
    [8] = {
      activePalette = true,
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
      minimized = true,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteName = "p1",
      rows = 1,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 0,
      selectedRow = 0,
      showGrid = "none",
      title = "Global palette 1",
      visibleCols = 4,
      visibleRows = 1,
      x = 531,
      y = 180,
      z = 80,
      zoom = 1
    },
    [9] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 8,
      delaysPerLayer = {
        [1] = 0.25
      },
      id = "oam_jumping_animation",
      kind = "oam_animation",
      layers = {
        [1] = {
          items = {
            [1] = { paletteNumber = 2, startAddr = 0x009644 },
            [2] = { paletteNumber = 2, startAddr = 0x009648 },
            [3] = { paletteNumber = 1, startAddr = 0x00964C },
            [4] = { paletteNumber = 1, startAddr = 0x009650 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_jumping",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 30,
          originY = 30,
          paletteData = {
            winId = "stage_01_sprites"
          }
        }
      },
      minimized = true,
      mirrorXPreview = false,
      multiRowToolbar = false,
      nonActiveLayerOpacity = 0,
      rows = 8,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = true,
      title = "OAM jumping animation",
      visibleCols = 8,
      visibleRows = 8,
      x = 262,
      y = 211,
      z = 90,
      zoom = 1
    },
    [10] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
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
      minimized = true,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Pattern table - Title screen BG (nametable)",
      visibleCols = 16,
      visibleRows = 16,
      x = 253,
      y = 136,
      z = 100,
      zoom = 1
    },
    [11] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 8,
      delaysPerLayer = {
        [1] = 0.25,
        [2] = 0.25,
        [3] = 0.25,
        [4] = 0.25,
        [5] = 0.25
      },
      id = "oam_static_poses",
      kind = "oam_animation",
      layers = {
        [1] = {
          items = {
            [1] = { paletteNumber = 2, startAddr = 0x0096B5 },
            [2] = { paletteNumber = 2, startAddr = 0x0096B9 },
            [3] = { paletteNumber = 2, startAddr = 0x0096BD },
            [4] = { paletteNumber = 1, startAddr = 0x00961C },
            [5] = { paletteNumber = 1, startAddr = 0x009624 },
            [6] = { paletteNumber = 1, startAddr = 0x009620 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_static_poses",
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
            [1] = { paletteNumber = 1, startAddr = 0x00961C },
            [2] = { paletteNumber = 1, startAddr = 0x009620 },
            [3] = { paletteNumber = 1, startAddr = 0x009624 },
            [4] = { paletteNumber = 2, startAddr = 0x00971D },
            [5] = { paletteNumber = 2, startAddr = 0x009721 },
            [6] = { paletteNumber = 2, startAddr = 0x009719 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_static_poses",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 30,
          originY = 35,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [3] = {
          items = {
            [1] = { paletteNumber = 1, startAddr = 0x009729 },
            [2] = { paletteNumber = 1, startAddr = 0x00972D },
            [3] = { paletteNumber = 2, startAddr = 0x009731 },
            [4] = { paletteNumber = 2, startAddr = 0x009735 }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_static_poses",
          mode = "8x16",
          name = "Frame 3",
          opacity = 1,
          originX = 30,
          originY = 35,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [4] = {
          items = {
            [1] = { paletteNumber = 2, startAddr = 0x009A25 },
            [2] = { paletteNumber = 2, startAddr = 0x009A29 },
            [3] = { paletteNumber = 1, startAddr = 0x009A31 },
            [4] = { paletteNumber = 1, startAddr = 0x009A35 },
            [5] = { paletteNumber = 1, startAddr = 0x009A39 },
            [6] = { paletteNumber = 1, startAddr = 0x009A3D },
            [7] = { paletteNumber = 2, startAddr = 0x009A2D }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_static_poses",
          mode = "8x16",
          name = "Frame 4",
          opacity = 1,
          originX = 30,
          originY = 35,
          paletteData = {
            winId = "stage_01_sprites"
          }
        },
        [5] = {
          items = {
            [1] = { paletteNumber = 2, startAddr = 0x009A76 },
            [2] = { paletteNumber = 2, startAddr = 0x009A72 },
            [3] = { paletteNumber = 1, startAddr = 0x009A7A },
            [4] = { paletteNumber = 1, startAddr = 0x009A7E },
            [5] = { paletteNumber = 1, startAddr = 0x009A82 },
            [6] = { paletteNumber = 1, startAddr = 0x009A86 },
            [7] = { paletteNumber = 1, startAddr = 0x009A8A }
          },
          kind = "sprite",
          linkedPatternTableWindowId = "pattern_table_oam_static_poses",
          mode = "8x16",
          name = "Frame 5",
          opacity = 1,
          originX = 30,
          originY = 35,
          paletteData = {
            winId = "stage_01_sprites"
          }
        }
      },
      minimized = true,
      mirrorXPreview = false,
      multiRowToolbar = false,
      nonActiveLayerOpacity = 0,
      rows = 9,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "OAM static poses",
      visibleCols = 8,
      visibleRows = 9,
      x = 54,
      y = 173,
      z = 110,
      zoom = 1
    },
    [12] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
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
                to = 447
              }
            }
          }
        }
      },
      minimized = true,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Pattern table - OAM running",
      visibleCols = 16,
      visibleRows = 16,
      x = 178,
      y = 178,
      z = 120,
      zoom = 1
    },
    [13] = {
      activeLayer = 5,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
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
            [1] = { paletteNumber = 1, startAddr = 0x0095FA },
            [2] = { paletteNumber = 1, startAddr = 0x0095F6 },
            [3] = { paletteNumber = 1, startAddr = 0x0095F2 },
            [4] = { paletteNumber = 2, startAddr = 0x0095EA },
            [5] = { paletteNumber = 2, startAddr = 0x0095EE }
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
            [1] = { paletteNumber = 2, startAddr = 0x009603 },
            [2] = { paletteNumber = 2, startAddr = 0x0095FF },
            [3] = { paletteNumber = 1, startAddr = 0x00960B },
            [4] = { paletteNumber = 1, startAddr = 0x009607 },
            [5] = { paletteNumber = 1, startAddr = 0x00960F }
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
            [1] = { paletteNumber = 1, startAddr = 0x009624 },
            [2] = { paletteNumber = 1, startAddr = 0x00961C },
            [3] = { paletteNumber = 1, startAddr = 0x009620 },
            [4] = { paletteNumber = 2, startAddr = 0x009614 },
            [5] = { paletteNumber = 2, startAddr = 0x009618 }
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
            [1] = { paletteNumber = 1, startAddr = 0x0095F2 },
            [2] = { paletteNumber = 1, startAddr = 0x0095FA },
            [3] = { paletteNumber = 1, startAddr = 0x0095F6 },
            [4] = { paletteNumber = 2, startAddr = 0x009629 },
            [5] = { paletteNumber = 2, startAddr = 0x00962D }
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
            [1] = { paletteNumber = 1, startAddr = 0x009607 },
            [2] = { paletteNumber = 1, startAddr = 0x00960B },
            [3] = { paletteNumber = 1, startAddr = 0x00960F },
            [4] = { paletteNumber = 2, startAddr = 0x0095FF },
            [5] = { paletteNumber = 2, startAddr = 0x009603 }
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
            [1] = { paletteNumber = 1, startAddr = 0x009624 },
            [2] = { paletteNumber = 1, startAddr = 0x00961C },
            [3] = { paletteNumber = 1, startAddr = 0x009620 },
            [4] = { paletteNumber = 2, startAddr = 0x009635 },
            [5] = { paletteNumber = 2, startAddr = 0x009639 }
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
      minimized = true,
      mirrorXPreview = false,
      multiRowToolbar = false,
      nonActiveLayerOpacity = 0,
      rows = 8,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "OAM running animation",
      visibleCols = 8,
      visibleRows = 8,
      x = 180,
      y = 215,
      z = 130,
      zoom = 1
    },
    [14] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = false,
      cols = 4,
      compactView = true,
      id = "rom_palette_2",
      kind = "rom_palette",
      minimized = true,
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
        userDefinedCode = "27,1,0;17,2,0;06,3,0;32,1,1;1C,2,1;02,3,1;20,1,2;37,2,2;26,3,2;10,1,3;00,2,3;02,3,3"
      },
      paletteName = "smooth_fbx",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 3,
      selectedRow = 1,
      showGrid = "chess",
      title = "Sprites cutscene 1 - Bill Rizer",
      visibleCols = 4,
      visibleRows = 4,
      x = 555,
      y = 44,
      z = 140,
      zoom = 1
    },
    [15] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 16,
      id = "pattern_table_oam_static_poses",
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
            }
          }
        }
      },
      minimized = true,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Pattern table - OAM static poses",
      visibleCols = 16,
      visibleRows = 16,
      x = 410,
      y = 186,
      z = 150,
      zoom = 1
    },
    [16] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 16,
      id = "pattern_table_oam_jumping",
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
            }
          }
        }
      },
      minimized = true,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 16,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Pattern table - OAM jumping",
      visibleCols = 16,
      visibleRows = 16,
      x = 331,
      y = 186,
      z = 160,
      zoom = 1
    },
    [17] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 16,
      currentBank = 16,
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
      orderMode = "oddEven",
      rows = 32,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Bank 16/16",
      visibleCols = 16,
      visibleRows = 32,
      x = 12,
      y = 41,
      z = 170,
      zoom = 1
    },
    [18] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 16,
      id = "pattern_table_cutscene_1",
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
      title = "Pattern table - Cutscene 1 (shared)",
      visibleCols = 16,
      visibleRows = 16,
      x = 170,
      y = 44,
      z = 180,
      zoom = 1
    },
    [19] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 32,
      id = "ppu_frame_3",
      kind = "ppu_frame",
      layers = {
        [1] = {
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
          },
          userDefinedAttrs = "000000000000000000000000000000000000551000000000004455110000000000a4aa2200000000008aaa220000000000000000000000000000000000000000"
        },
        [2] = {
          items = {
            [1] = { paletteNumber = 3, startAddr = 0x00A2DE },
            [2] = { paletteNumber = 3, startAddr = 0x00A2E6 },
            [3] = { paletteNumber = 3, startAddr = 0x00A2EA },
            [4] = { paletteNumber = 3, startAddr = 0x00A2F2 },
            [5] = { paletteNumber = 3, startAddr = 0x00A2EE },
            [6] = { paletteNumber = 1, startAddr = 0x009B23 },
            [7] = { paletteNumber = 1, startAddr = 0x009B27 },
            [8] = { paletteNumber = 2, startAddr = 0x009B2B },
            [9] = { paletteNumber = 2, startAddr = 0x009B2F },
            [10] = { paletteNumber = 2, startAddr = 0x009B33 },
            [11] = { paletteNumber = 2, startAddr = 0x009B37 },
            [12] = { paletteNumber = 2, startAddr = 0x009B3B },
            [13] = { paletteNumber = 2, startAddr = 0x009B3F },
            [14] = { paletteNumber = 4, startAddr = 0x009B43 },
            [15] = { paletteNumber = 4, startAddr = 0x009B47 },
            [16] = { paletteNumber = 4, startAddr = 0x009B4B },
            [17] = { paletteNumber = 4, startAddr = 0x009B4F },
            [18] = { paletteNumber = 2, startAddr = 0x009B1F },
            [19] = { paletteNumber = 4, startAddr = 0x009B53 },
            [20] = { paletteNumber = 2, startAddr = 0x009B17 },
            [21] = { paletteNumber = 4, startAddr = 0x009B57 },
            [22] = { paletteNumber = 1, startAddr = 0x009C12 },
            [23] = { paletteNumber = 1, startAddr = 0x009C1A },
            [24] = { paletteNumber = 1, startAddr = 0x009B6E },
            [25] = { paletteNumber = 2, startAddr = 0x009B72 },
            [26] = { paletteNumber = 2, startAddr = 0x009B1B },
            [27] = { paletteNumber = 3, startAddr = 0x00A2E2 }
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
      scrollRow = 7,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "Cutscene 1 - Lance",
      visibleCols = 18,
      visibleRows = 18,
      x = 471,
      y = 46,
      z = 190,
      zoom = 1
    },
    [20] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 8,
      id = "static_art_1",
      kind = "static_art",
      layers = {
        [1] = {
          items = {
          },
          kind = "tile",
          name = "Layer 1",
          opacity = 1
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 8,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "New Window",
      visibleCols = 8,
      visibleRows = 8,
      x = 529,
      y = 235,
      z = 200,
      zoom = 1
    },
    [21] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 32,
      id = "ppu_frame_1",
      kind = "ppu_frame",
      layers = {
        [1] = {
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
          },
          userDefinedAttrs = "000000000000000000000000000000000000551000000000004455110000000000a4aa2200000000008aaa220000000000000000000000000000000000000000"
        },
        [2] = {
          items = {
            [1] = { paletteNumber = 3, startAddr = 0x009B0B },
            [2] = { paletteNumber = 3, startAddr = 0x009B13 },
            [3] = { paletteNumber = 1, startAddr = 0x009B23 },
            [4] = { paletteNumber = 1, startAddr = 0x009B27 },
            [5] = { paletteNumber = 2, startAddr = 0x009B2B },
            [6] = { paletteNumber = 2, startAddr = 0x009B2F },
            [7] = { paletteNumber = 2, startAddr = 0x009B33 },
            [8] = { paletteNumber = 2, startAddr = 0x009B37 },
            [9] = { paletteNumber = 2, startAddr = 0x009B3B },
            [10] = { paletteNumber = 2, startAddr = 0x009B3F },
            [11] = { paletteNumber = 4, startAddr = 0x009B43 },
            [12] = { paletteNumber = 4, startAddr = 0x009B47 },
            [13] = { paletteNumber = 4, startAddr = 0x009B4B },
            [14] = { paletteNumber = 4, startAddr = 0x009B4F },
            [15] = { paletteNumber = 2, startAddr = 0x009B1F },
            [16] = { paletteNumber = 4, startAddr = 0x009B53 },
            [17] = { paletteNumber = 2, startAddr = 0x009B17 },
            [18] = { paletteNumber = 4, startAddr = 0x009B57 },
            [19] = { paletteNumber = 1, startAddr = 0x009C12 },
            [20] = { paletteNumber = 1, startAddr = 0x009C1A },
            [21] = { paletteNumber = 1, startAddr = 0x009B6E },
            [22] = { paletteNumber = 2, startAddr = 0x009B72 },
            [23] = { paletteNumber = 2, startAddr = 0x009B1B },
            [24] = { paletteNumber = 3, startAddr = 0x009B07 },
            [25] = { paletteNumber = 3, startAddr = 0x009B0F },
            [26] = { paletteNumber = 3, startAddr = 0x009B03 }
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
      scrollCol = 2,
      scrollRow = 7,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "Cutscene 1 - Bill",
      visibleCols = 16,
      visibleRows = 17,
      x = 319,
      y = 46,
      z = 210,
      zoom = 1
    },
    [22] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = false,
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
        userDefinedCode = "20,1,0;20,2,0;0F,3,0;27,1,1;17,2,1;07,3,1;19,1,2;09,2,2;17,3,2;2C,1,3;09,2,3;06,3,3"
      },
      paletteName = "smooth_fbx",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 2,
      selectedRow = 2,
      showGrid = "chess",
      title = "BG cutscene 1 - Bill",
      visibleCols = 4,
      visibleRows = 4,
      x = 395,
      y = 249,
      z = 220,
      zoom = 1
    },
    [23] = {
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
          },
          userDefinedAttrs = "000080a0a02000000000080a0a0200000000000000000000000405050505010000000000ccfff30000000000ffffcc0000000000000000000000000000000000"
        },
        [2] = {
          items = {
            [1] = { paletteNumber = 1, startAddr = 0x009F2B },
            [2] = { paletteNumber = 1, startAddr = 0x009F57 },
            [3] = { paletteNumber = 1, startAddr = 0x009F43 },
            [4] = { paletteNumber = 2, startAddr = 0x009F03 },
            [5] = { paletteNumber = 3, startAddr = 0x009F3B },
            [6] = { paletteNumber = 3, startAddr = 0x009F3F },
            [7] = { paletteNumber = 3, startAddr = 0x009F33 },
            [8] = { paletteNumber = 3, startAddr = 0x009F37 },
            [9] = { paletteNumber = 3, startAddr = 0x009F13 },
            [10] = { paletteNumber = 1, startAddr = 0x009F47 },
            [11] = { paletteNumber = 1, startAddr = 0x009F27 },
            [12] = { paletteNumber = 3, startAddr = 0x009F0F },
            [13] = { paletteNumber = 1, startAddr = 0x009F1F },
            [14] = { paletteNumber = 3, startAddr = 0x009F17 },
            [15] = { paletteNumber = 2, startAddr = 0x009F0B },
            [16] = { paletteNumber = 1, startAddr = 0x009F1B },
            [17] = { paletteNumber = 2, startAddr = 0x009F07 },
            [18] = { paletteNumber = 1, startAddr = 0x009F4F },
            [19] = { paletteNumber = 1, startAddr = 0x009F2F },
            [20] = { paletteNumber = 1, startAddr = 0x009F4B },
            [21] = { paletteNumber = 1, startAddr = 0x009F23 },
            [22] = { paletteNumber = 1, startAddr = 0x009F53 }
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
      scrollCol = 15,
      scrollRow = 13,
      showGrid = "chess",
      showSpriteOriginGuides = true,
      title = "Title screen",
      visibleCols = 13,
      visibleRows = 15,
      x = 209,
      y = 178,
      z = 230,
      zoom = 1
    }
  }
}
