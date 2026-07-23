return {
  currentBank = 4,
  currentColor = 0,
  edits = {
    banks = {
    }
  },
  focusedWindowId = "animation_9",
  kind = "project",
  projectVersion = 1,
  romPatches = {
    [1] = {
      address = 0x01C060,
      reason = "Change game over screen table pointer, to point to new location in ROM",
      value = 0xAC
    }
  },
  syncDuplicateTiles = false,
  windowOrderIds = {
    [1] = "bank",
    [2] = "ppu_frame_1",
    [3] = "palette_01",
    [4] = "palette_1",
    [5] = "rom_palette_1",
    [6] = "pattern_table_1",
    [7] = "static_art_2",
    [8] = "animation_1",
    [9] = "static_art_3",
    [10] = "static_art_4",
    [11] = "animation_2",
    [12] = "animation_4",
    [13] = "animation_3",
    [14] = "animation_5",
    [15] = "animation_8",
    [16] = "animation_9"
  },
  windows = {
    [1] = {
      activePalette = false,
      alwaysOnTop = false,
      collapsed = false,
      cols = 4,
      compactView = false,
      id = "palette_01",
      items = {
        [1] = { code = "16", col = 0, row = 0 },
        [2] = { code = "30", col = 1, row = 0 },
        [3] = { code = "27", col = 2, row = 0 },
        [4] = { code = "0F", col = 3, row = 0 }
      },
      kind = "palette",
      minimized = true,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteName = "smooth_fbx",
      rows = 1,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 0,
      selectedRow = 0,
      showGrid = "none",
      title = "Game over",
      visibleCols = 4,
      visibleRows = 1,
      x = 213,
      y = 268,
      z = 10,
      zoom = 1
    },
    [2] = {
      activePalette = true,
      alwaysOnTop = false,
      collapsed = false,
      cols = 4,
      compactView = true,
      id = "palette_1",
      items = {
        [1] = { code = "00", col = 0, row = 0 },
        [2] = { code = "0B", col = 1, row = 0 },
        [3] = { code = "26", col = 2, row = 0 },
        [4] = { code = "19", col = 3, row = 0 }
      },
      kind = "palette",
      minimized = true,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      paletteName = "smooth_fbx",
      rows = 1,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 1,
      selectedRow = 0,
      showGrid = "chess",
      title = "Link sidescroll",
      visibleCols = 4,
      visibleRows = 1,
      x = 241,
      y = 254,
      z = 20,
      zoom = 1
    },
    [3] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 16,
      id = "pattern_table_1",
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
                bank = 9,
                from = 256,
                to = 511
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
      title = "gameover screen",
      visibleCols = 16,
      visibleRows = 16,
      x = 182,
      y = 55,
      z = 30,
      zoom = 1
    },
    [4] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 8,
      id = "static_art_2",
      kind = "static_art",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, mirrorX = true, tile = 0, x = 16, y = 8 },
            [2] = { bank = 4, mirrorX = true, tile = 2, x = 8, y = 8 },
            [3] = { bank = 4, mirrorX = true, tile = 6, x = 8, y = 24 },
            [4] = { bank = 4, mirrorX = true, tile = 38, x = 16, y = 24 },
            [5] = { bank = 4, tile = 2, x = 48, y = 8 },
            [6] = { bank = 4, tile = 0, x = 40, y = 8 },
            [7] = { bank = 4, tile = 6, x = 48, y = 24 },
            [8] = { bank = 4, tile = 38, x = 40, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Layer 1",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 6,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Link Idle",
      visibleCols = 8,
      visibleRows = 6,
      x = 147,
      y = 37,
      z = 40,
      zoom = 2
    },
    [5] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 8,
      id = "static_art_3",
      kind = "static_art",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, mirrorX = true, tile = 74, x = 16, y = 24 },
            [2] = { bank = 4, mirrorX = true, tile = 76, x = 8, y = 24 },
            [3] = { bank = 4, mirrorX = true, tile = 70, x = 16, y = 8 },
            [4] = { bank = 4, mirrorX = true, tile = 72, x = 8, y = 8 },
            [5] = { bank = 4, tile = 74, x = 40, y = 24 },
            [6] = { bank = 4, tile = 76, x = 48, y = 24 },
            [7] = { bank = 4, tile = 70, x = 40, y = 8 },
            [8] = { bank = 4, tile = 72, x = 48, y = 8 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Layer 1",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 6,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Link Ducking (used for jumping too)",
      visibleCols = 8,
      visibleRows = 6,
      x = 158,
      y = 57,
      z = 50,
      zoom = 2
    },
    [6] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 4,
      delaysPerLayer = {
        [1] = 0.1,
        [2] = 0.1,
        [3] = 0.1
      },
      id = "animation_1",
      kind = "animation",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, mirrorX = true, tile = 4, x = 16, y = 24 },
            [2] = { bank = 4, mirrorX = true, tile = 6, x = 8, y = 24 },
            [3] = { bank = 4, mirrorX = true, tile = 0, x = 16, y = 8 },
            [4] = { bank = 4, mirrorX = true, tile = 2, x = 8, y = 8 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 0,
          originY = 0
        },
        [2] = {
          items = {
            [1] = { bank = 4, mirrorX = true, tile = 12, x = 16, y = 24 },
            [2] = { bank = 4, mirrorX = true, tile = 14, x = 8, y = 24 },
            [3] = { bank = 4, mirrorX = true, tile = 8, x = 16, y = 8 },
            [4] = { bank = 4, mirrorX = true, tile = 10, x = 8, y = 8 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 0,
          originY = 0
        },
        [3] = {
          items = {
            [1] = { bank = 4, mirrorX = true, tile = 0, x = 16, y = 8 },
            [2] = { bank = 4, mirrorX = true, tile = 16, x = 16, y = 24 },
            [3] = { bank = 4, mirrorX = true, tile = 18, x = 8, y = 24 },
            [4] = { bank = 4, mirrorX = true, tile = 2, x = 8, y = 8 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 3",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 0,
      rows = 6,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Link walking",
      visibleCols = 4,
      visibleRows = 6,
      x = 174,
      y = 80,
      z = 60,
      zoom = 2
    },
    [7] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 7,
      id = "animation_2",
      kind = "animation",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, tile = 40, x = 24, y = 8 },
            [2] = { bank = 4, tile = 42, x = 32, y = 8 },
            [3] = { bank = 4, tile = 48, x = 40, y = 8 },
            [4] = { bank = 4, tile = 44, x = 24, y = 24 },
            [5] = { bank = 4, tile = 46, x = 32, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 0,
          originY = 0
        },
        [2] = {
          items = {
            [1] = { bank = 4, tile = 58, x = 24, y = 24 },
            [2] = { bank = 4, tile = 60, x = 32, y = 24 },
            [3] = { bank = 4, tile = 50, x = 8, y = 8 },
            [4] = { bank = 4, tile = 52, x = 16, y = 8 },
            [5] = { bank = 4, tile = 54, x = 24, y = 8 },
            [6] = { bank = 4, tile = 56, x = 32, y = 8 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 0,
          originY = 0
        },
        [3] = {
          items = {
            [1] = { bank = 4, tile = 2, x = 32, y = 8 },
            [2] = { bank = 4, tile = 0, x = 24, y = 8 },
            [3] = { bank = 4, tile = 6, x = 32, y = 24 },
            [4] = { bank = 4, tile = 38, x = 24, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 3",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 0,
      rows = 6,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Link attacking",
      visibleCols = 7,
      visibleRows = 6,
      x = 186,
      y = 109,
      z = 70,
      zoom = 2
    },
    [8] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 8,
      id = "static_art_4",
      kind = "static_art",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, tile = 20, x = 8, y = 8 },
            [2] = { bank = 4, tile = 22, x = 16, y = 8 },
            [3] = { bank = 4, tile = 24, x = 8, y = 24 },
            [4] = { bank = 4, tile = 26, x = 16, y = 24 },
            [5] = { bank = 4, mirrorX = true, tile = 20, x = 48, y = 8 },
            [6] = { bank = 4, mirrorX = true, tile = 22, x = 40, y = 8 },
            [7] = { bank = 4, mirrorX = true, tile = 24, x = 48, y = 24 },
            [8] = { bank = 4, mirrorX = true, tile = 26, x = 40, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Layer 1",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 6,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Link hurt",
      visibleCols = 8,
      visibleRows = 6,
      x = 200,
      y = 133,
      z = 80,
      zoom = 2
    },
    [9] = {
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
          codec = "zelda2",
          items = {
          },
          kind = "tile",
          linkedPatternTableWindowId = "pattern_table_1",
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x0000D8,
          nametableStartAddr = 0x000010,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_1"
          },
          relocateTo = 0x002C10
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 4,
      scrollRow = 7,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "Game Over",
      visibleCols = 24,
      visibleRows = 23,
      x = 404,
      y = 35,
      z = 90,
      zoom = 1
    },
    [10] = {
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
            [1] = 0x0000DC,
            [2] = 0x0000DD,
            [3] = 0x0000DE,
            [4] = 0x0000DF
          },
          [2] = {
            [1] = 0x0000E0,
            [2] = 0x0000E1,
            [3] = 0x0000E2,
            [4] = 0x0000E3
          },
          [3] = {
            [1] = false,
            [2] = false,
            [3] = false,
            [4] = false
          },
          [4] = {
            [1] = false,
            [2] = false,
            [3] = false,
            [4] = false
          }
        },
        userDefinedCode = "16,0,0;30,1,0;0F,2,0;0F,3,0;16,0,1;30,1,1;27,2,1;0F,3,1"
      },
      paletteName = "smooth_fbx",
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 2,
      selectedRow = 0,
      showGrid = "chess",
      title = "Ganon GameOver palette",
      visibleCols = 4,
      visibleRows = 4,
      x = 521,
      y = 57,
      z = 100,
      zoom = 1
    },
    [11] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 4,
      id = "animation_5",
      kind = "animation",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, tile = 216, x = 8, y = 8 },
            [2] = { bank = 4, tile = 224, x = 8, y = 24 },
            [3] = { bank = 4, tile = 226, x = 16, y = 24 },
            [4] = { bank = 4, tile = 218, x = 16, y = 8 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 0,
          originY = 0
        },
        [2] = {
          items = {
            [1] = { bank = 4, tile = 216, x = 8, y = 8 },
            [2] = { bank = 4, tile = 218, x = 16, y = 8 },
            [3] = { bank = 4, tile = 228, x = 8, y = 24 },
            [4] = { bank = 4, tile = 230, x = 16, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 0,
      rows = 6,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "NPC 2",
      visibleCols = 4,
      visibleRows = 6,
      x = 323,
      y = 227,
      z = 110,
      zoom = 2
    },
    [12] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 4,
      id = "animation_3",
      kind = "animation",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, tile = 240, x = 8, y = 24 },
            [2] = { bank = 4, tile = 242, x = 16, y = 24 },
            [3] = { bank = 4, tile = 232, x = 8, y = 8 },
            [4] = { bank = 4, tile = 234, x = 16, y = 8 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 0,
          originY = 0
        },
        [2] = {
          items = {
            [1] = { bank = 4, tile = 234, x = 16, y = 8 },
            [2] = { bank = 4, tile = 232, x = 8, y = 8 },
            [3] = { bank = 4, tile = 236, x = 8, y = 24 },
            [4] = { bank = 4, tile = 238, x = 16, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 0,
      rows = 6,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "NPC 1",
      visibleCols = 4,
      visibleRows = 6,
      x = 246,
      y = 224,
      z = 120,
      zoom = 2
    },
    [13] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 3,
      delaysPerLayer = {
        [1] = 0.1,
        [2] = 0.1
      },
      id = "animation_4",
      kind = "animation",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, tile = 104, x = 8, y = 8 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 0,
          originY = 0
        },
        [2] = {
          items = {
            [1] = { bank = 4, tile = 106, x = 8, y = 8 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 0,
      rows = 4,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Fairy",
      visibleCols = 3,
      visibleRows = 4,
      x = 162,
      y = 224,
      z = 130,
      zoom = 3
    },
    [14] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 4,
      id = "animation_8",
      kind = "animation",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, tile = 220, x = 8, y = 8 },
            [2] = { bank = 4, tile = 222, x = 16, y = 8 },
            [3] = { bank = 4, tile = 224, x = 8, y = 24 },
            [4] = { bank = 4, tile = 226, x = 16, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 0,
          originY = 0
        },
        [2] = {
          items = {
            [1] = { bank = 4, tile = 220, x = 8, y = 8 },
            [2] = { bank = 4, tile = 222, x = 16, y = 8 },
            [3] = { bank = 4, tile = 228, x = 8, y = 24 },
            [4] = { bank = 4, tile = 230, x = 16, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 0,
      rows = 6,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "NPC 3",
      visibleCols = 4,
      visibleRows = 6,
      x = 395,
      y = 228,
      z = 140,
      zoom = 2
    },
    [15] = {
      activeLayer = 1,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 16,
      currentBank = 4,
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
      title = "Bank 4/16",
      visibleCols = 16,
      visibleRows = 32,
      x = 4,
      y = 53,
      z = 150,
      zoom = 1
    },
    [16] = {
      activeLayer = 2,
      alwaysOnTop = false,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 4,
      delaysPerLayer = {
        [1] = 0.25,
        [2] = 0.25
      },
      id = "animation_9",
      kind = "animation",
      layers = {
        [1] = {
          items = {
            [1] = { bank = 4, tile = 244, x = 8, y = 8 },
            [2] = { bank = 4, tile = 246, x = 16, y = 8 },
            [3] = { bank = 4, tile = 248, x = 8, y = 24 },
            [4] = { bank = 4, tile = 250, x = 16, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 1",
          opacity = 1,
          originX = 0,
          originY = 0
        },
        [2] = {
          items = {
            [1] = { bank = 4, tile = 244, x = 8, y = 8 },
            [2] = { bank = 4, tile = 246, x = 16, y = 8 },
            [3] = { bank = 4, tile = 252, x = 8, y = 24 },
            [4] = { bank = 4, tile = 254, x = 16, y = 24 }
          },
          kind = "sprite",
          mode = "8x16",
          name = "Frame 2",
          opacity = 1,
          originX = 0,
          originY = 0
        }
      },
      minimized = false,
      mirrorXPreview = false,
      nonActiveLayerOpacity = 0,
      rows = 6,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "Old lady",
      visibleCols = 4,
      visibleRows = 6,
      x = 474,
      y = 226,
      z = 160,
      zoom = 2
    }
  }
}
