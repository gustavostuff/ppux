return {
  currentBank = 6,
  currentColor = 3,
  edits = {
    banks = {
      -- Even tho DB entries should not contain pixel edits, I am making an exception here.
      -- See this: https://i.ibb.co/pjv6QYJM/explanation-on-edits.png
      [6] = {
        ["160"] = "-1:5;3:1;-1:15;3:1;-1:6;3:1;-1:8;3:1;-1:6;3:1;0:1;-1:7;0:2;-1:5;3:2;0:1;-1:1",
        ["161"] = "-1:4;3:1;-1:6;3:1;2:1;3:2;-1:2;3:1;-1:1;3:1;2:1;3:1;-1:2;3:1;-1:2;3:1;2:1;3:1;0:1;-1:4;3:1;2:2;-1:2;3:2;-1:1;3:1;2:2;-1:2;1:2;3:1;2:3;3:2;1:4;2:1;-1:1;3:1;0:1",
        ["162"] = "0:2;-1:3;1:3;-1:7;1:1;-1:48",
        ["177"] = "-1:46;2:1;-1:6;2:2;-1:5;2:2;-1:2",
        ["179"] = "-1:19;3:1;-1:8;3:1;-1:6;3:1;-1:6;3:2;-1:6;3:1;-1:13",
        ["182"] = "-1:6;2:1;3:1;-1:5;3:1;-1:1;3:1;-1:5;2:1;-1:15;3:1;-1:26",
        ["184"] = "-1:1;3:1;-1:15;0:1;-1:6;0:1;-1:39",
        ["238"] = "-1:54;3:1;-1:6;3:1;-1:2",
        ["239"] = "-1:4;3:1;-1:59"
      }
    }
  },
  focusedWindowId = "rom_palette_2",
  kind = "project",
  projectVersion = 1,
  syncDuplicateTiles = false,
  windows = {
    [1] = {
      activeLayer = 1,
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
            [1] = { bank = 1, paletteNumber = 2, startAddr = 0x0096B5, tile = 404 },
            [2] = { bank = 1, paletteNumber = 2, startAddr = 0x0096B9, tile = 406 },
            [3] = { bank = 1, paletteNumber = 2, startAddr = 0x0096BD, tile = 408 },
            [4] = { bank = 1, paletteNumber = 1, startAddr = 0x00961C, tile = 124 },
            [5] = { bank = 1, paletteNumber = 1, startAddr = 0x009624, tile = 258 },
            [6] = { bank = 1, paletteNumber = 1, startAddr = 0x009620, tile = 126 }
          },
          kind = "sprite",
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
            [1] = { bank = 1, paletteNumber = 1, startAddr = 0x00961C, tile = 124 },
            [2] = { bank = 1, paletteNumber = 1, startAddr = 0x009620, tile = 126 },
            [3] = { bank = 1, paletteNumber = 1, startAddr = 0x009624, tile = 258 },
            [4] = { bank = 1, paletteNumber = 2, startAddr = 0x00971D, tile = 384 },
            [5] = { bank = 1, paletteNumber = 2, startAddr = 0x009721, tile = 388 },
            [6] = { bank = 1, paletteNumber = 2, startAddr = 0x009719, tile = 386 }
          },
          kind = "sprite",
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
            [1] = { bank = 1, paletteNumber = 1, startAddr = 0x009729, tile = 412 },
            [2] = { bank = 1, paletteNumber = 1, startAddr = 0x00972D, tile = 414 },
            [3] = { bank = 1, paletteNumber = 2, startAddr = 0x009731, tile = 416 },
            [4] = { bank = 1, paletteNumber = 2, startAddr = 0x009735, tile = 418 }
          },
          kind = "sprite",
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
            [1] = { bank = 1, paletteNumber = 2, startAddr = 0x009A25, tile = 380 },
            [2] = { bank = 1, paletteNumber = 2, startAddr = 0x009A29, tile = 382 },
            [3] = { bank = 1, paletteNumber = 1, startAddr = 0x009A31, tile = 376 },
            [4] = { bank = 1, paletteNumber = 1, startAddr = 0x009A35, tile = 376 },
            [5] = { bank = 1, paletteNumber = 1, startAddr = 0x009A39, tile = 378 },
            [6] = { bank = 1, paletteNumber = 1, startAddr = 0x009A3D, tile = 378 },
            [7] = { bank = 2, paletteNumber = 2, startAddr = 0x009A2D, tile = 0 }
          },
          kind = "sprite",
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
            [1] = { bank = 2, paletteNumber = 2, startAddr = 0x009A76, tile = 4 },
            [2] = { bank = 2, paletteNumber = 2, startAddr = 0x009A72, tile = 2 },
            [3] = { bank = 2, paletteNumber = 1, startAddr = 0x009A7A, tile = 6 },
            [4] = { bank = 2, paletteNumber = 1, startAddr = 0x009A7E, tile = 6 },
            [5] = { bank = 2, paletteNumber = 1, startAddr = 0x009A82, tile = 8 },
            [6] = { bank = 2, paletteNumber = 1, startAddr = 0x009A86, tile = 8 },
            [7] = { bank = 2, paletteNumber = 1, startAddr = 0x009A8A, tile = 10 }
          },
          kind = "sprite",
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
      x = 196,
      y = 215,
      z = 10,
      zoom = 1
    },
    [2] = {
      activeLayer = 1,
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
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x010160,
          nametableStartAddr = 0x010011,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_01"
          },
          patternTable = {
            ranges = {
              [1] = {
                bank = 9,
                page = 1,
                tileRange = {
                  from = 0,
                  to = 255
                }
              }
            }
          },
          userDefinedAttrs = "000080a0a02000000000080a0a0200000000000000000000000405050505010000000000fffff33300000000ffffcc0f00000000000000000000000000000000"
        },
        [2] = {
          items = {
            [1] = { bank = 4, paletteNumber = 1, startAddr = 0x009F2B, tile = 238 },
            [2] = { bank = 4, paletteNumber = 1, startAddr = 0x009F57, tile = 252 },
            [3] = { bank = 4, paletteNumber = 1, startAddr = 0x009F43, tile = 230 },
            [4] = { bank = 4, paletteNumber = 2, startAddr = 0x009F03, tile = 218 },
            [5] = { bank = 4, paletteNumber = 3, startAddr = 0x009F3B, tile = 210 },
            [6] = { bank = 4, paletteNumber = 3, startAddr = 0x009F3F, tile = 216 },
            [7] = { bank = 4, paletteNumber = 3, startAddr = 0x009F33, tile = 214 },
            [8] = { bank = 4, paletteNumber = 3, startAddr = 0x009F37, tile = 212 },
            [9] = { bank = 4, paletteNumber = 3, startAddr = 0x009F13, tile = 224 },
            [10] = { bank = 4, paletteNumber = 1, startAddr = 0x009F47, tile = 232 },
            [11] = { bank = 4, paletteNumber = 1, startAddr = 0x009F27, tile = 246 },
            [12] = { bank = 4, paletteNumber = 3, startAddr = 0x009F0F, tile = 220 },
            [13] = { bank = 4, paletteNumber = 1, startAddr = 0x009F1F, tile = 244 },
            [14] = { bank = 4, paletteNumber = 3, startAddr = 0x009F17, tile = 228 },
            [15] = { bank = 4, paletteNumber = 2, startAddr = 0x009F0B, tile = 226 },
            [16] = { bank = 4, paletteNumber = 1, startAddr = 0x009F1B, tile = 234 },
            [17] = { bank = 4, paletteNumber = 2, startAddr = 0x009F07, tile = 222 },
            [18] = { bank = 4, paletteNumber = 1, startAddr = 0x009F4F, tile = 250 },
            [19] = { bank = 4, paletteNumber = 1, startAddr = 0x009F2F, tile = 248 },
            [20] = { bank = 4, paletteNumber = 1, startAddr = 0x009F4B, tile = 240 },
            [21] = { bank = 4, paletteNumber = 1, startAddr = 0x009F23, tile = 236 },
            [22] = { bank = 4, paletteNumber = 1, startAddr = 0x009F53, tile = 242 }
          },
          kind = "sprite",
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
      minimized = true,
      nonActiveLayerOpacity = 0,
      rows = 30,
      scrollCol = 8,
      scrollRow = 12,
      showGrid = "chess",
      showSpriteOriginGuides = true,
      title = "Title screen",
      visibleCols = 18,
      visibleRows = 18,
      x = 487,
      y = 155,
      z = 20,
      zoom = 1
    },
    [3] = {
      activeLayer = 1,
      cellH = 8,
      cellW = 8,
      collapsed = false,
      cols = 16,
      currentBank = 6,
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
      nonActiveLayerOpacity = 1,
      orderMode = "normal",
      rows = 32,
      scrollCol = 0,
      scrollRow = 0,
      showGrid = "chess",
      title = "CHR banks",
      visibleCols = 16,
      visibleRows = 32,
      x = 38,
      y = 50,
      z = 30,
      zoom = 1
    },
    [4] = {
      activeLayer = 1,
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
            [1] = { bank = 1, paletteNumber = 2, startAddr = 0x009644, tile = 260 },
            [2] = { bank = 1, paletteNumber = 2, startAddr = 0x009648, tile = 264 },
            [3] = { bank = 1, paletteNumber = 1, startAddr = 0x00964C, tile = 262 },
            [4] = { bank = 1, paletteNumber = 1, startAddr = 0x009650, tile = 266 }
          },
          kind = "sprite",
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
      minimized = false,
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
      x = 528,
      y = 37,
      z = 40,
      zoom = 1
    },
    [5] = {
      activePalette = true,
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
      z = 50,
      zoom = 1
    },
    [6] = {
      activeLayer = 4,
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
            [1] = { bank = 1, paletteNumber = 1, startAddr = 0x0095FA, tile = 256 },
            [2] = { bank = 1, paletteNumber = 1, startAddr = 0x0095F6, tile = 118 },
            [3] = { bank = 1, paletteNumber = 1, startAddr = 0x0095F2, tile = 116 },
            [4] = { bank = 1, paletteNumber = 2, startAddr = 0x0095EA, tile = 104 },
            [5] = { bank = 1, paletteNumber = 2, startAddr = 0x0095EE, tile = 106 }
          },
          kind = "sprite",
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
            [1] = { bank = 1, paletteNumber = 2, startAddr = 0x009603, tile = 110 },
            [2] = { bank = 1, paletteNumber = 2, startAddr = 0x0095FF, tile = 108 },
            [3] = { bank = 1, paletteNumber = 1, startAddr = 0x00960B, tile = 122 },
            [4] = { bank = 1, paletteNumber = 1, startAddr = 0x009607, tile = 120 },
            [5] = { bank = 1, paletteNumber = 1, startAddr = 0x00960F, tile = 258 }
          },
          kind = "sprite",
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
            [1] = { bank = 1, paletteNumber = 1, startAddr = 0x009624, tile = 258 },
            [2] = { bank = 1, paletteNumber = 1, startAddr = 0x00961C, tile = 124 },
            [3] = { bank = 1, paletteNumber = 1, startAddr = 0x009620, tile = 126 },
            [4] = { bank = 1, paletteNumber = 2, startAddr = 0x009614, tile = 112 },
            [5] = { bank = 1, paletteNumber = 2, startAddr = 0x009618, tile = 114 }
          },
          kind = "sprite",
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
            [1] = { bank = 1, paletteNumber = 1, startAddr = 0x0095F2, tile = 116 },
            [2] = { bank = 1, paletteNumber = 1, startAddr = 0x0095FA, tile = 256 },
            [3] = { bank = 1, paletteNumber = 1, startAddr = 0x0095F6, tile = 118 },
            [4] = { bank = 1, paletteNumber = 2, startAddr = 0x009629, tile = 112 },
            [5] = { bank = 1, paletteNumber = 2, startAddr = 0x00962D, tile = 114 }
          },
          kind = "sprite",
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
            [1] = { bank = 1, paletteNumber = 1, startAddr = 0x009607, tile = 120 },
            [2] = { bank = 1, paletteNumber = 1, startAddr = 0x00960B, tile = 122 },
            [3] = { bank = 1, paletteNumber = 1, startAddr = 0x00960F, tile = 258 },
            [4] = { bank = 1, paletteNumber = 2, startAddr = 0x0095FF, tile = 108 },
            [5] = { bank = 1, paletteNumber = 2, startAddr = 0x009603, tile = 110 }
          },
          kind = "sprite",
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
            [1] = { bank = 1, paletteNumber = 1, startAddr = 0x009624, tile = 258 },
            [2] = { bank = 1, paletteNumber = 1, startAddr = 0x00961C, tile = 124 },
            [3] = { bank = 1, paletteNumber = 1, startAddr = 0x009620, tile = 126 },
            [4] = { bank = 1, paletteNumber = 2, startAddr = 0x009635, tile = 104 },
            [5] = { bank = 1, paletteNumber = 2, startAddr = 0x009639, tile = 106 }
          },
          kind = "sprite",
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
      x = 535,
      y = 231,
      z = 60,
      zoom = 1
    },
    [7] = {
      activePalette = false,
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
      nonActiveLayerOpacity = 1,
      paletteName = "p1",
      rows = 1,
      scrollCol = 0,
      scrollRow = 0,
      selectedCol = 2,
      selectedRow = 0,
      showGrid = "none",
      title = "Global palette 1",
      visibleCols = 4,
      visibleRows = 1,
      x = 531,
      y = 180,
      z = 70,
      zoom = 1
    },
    [8] = {
      activePalette = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "stage_01_sprites",
      kind = "rom_palette",
      minimized = false,
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
      z = 80,
      zoom = 1
    },
    [9] = {
      activePalette = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_02",
      kind = "rom_palette",
      minimized = false,
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
      z = 90,
      zoom = 1
    },
    [10] = {
      activePalette = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_01",
      kind = "rom_palette",
      minimized = false,
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
      z = 100,
      zoom = 1
    },
    [11] = {
      activeLayer = 2,
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
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x01255A,
          nametableStartAddr = 0x012493,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_1"
          },
          patternTable = {
            ranges = {
              [1] = {
                bank = 16,
                page = 1,
                tileRange = {
                  from = 128,
                  to = 191
                }
              },
              [2] = {
                bank = 6,
                page = 1,
                tileRange = {
                  from = 64,
                  to = 255
                }
              }
            }
          },
          userDefinedAttrs = "000000000000000000000000000000000000551000000000004455110000000000a4aa2200000000008aaa220000000000000000000000000000000000000000"
        },
        [2] = {
          items = {
            [1] = { bank = 6, paletteNumber = 3, startAddr = 0x009B0B, tile = 228 },
            [2] = { bank = 6, paletteNumber = 3, startAddr = 0x009B13, tile = 232 },
            [3] = { bank = 6, paletteNumber = 1, startAddr = 0x009B23, tile = 216 },
            [4] = { bank = 6, paletteNumber = 1, startAddr = 0x009B27, tile = 218 },
            [5] = { bank = 6, paletteNumber = 2, startAddr = 0x009B2B, tile = 204 },
            [6] = { bank = 6, paletteNumber = 2, startAddr = 0x009B2F, tile = 206 },
            [7] = { bank = 6, paletteNumber = 2, startAddr = 0x009B33, tile = 208 },
            [8] = { bank = 6, paletteNumber = 2, startAddr = 0x009B37, tile = 210 },
            [9] = { bank = 6, paletteNumber = 2, startAddr = 0x009B3B, tile = 212 },
            [10] = { bank = 6, paletteNumber = 2, startAddr = 0x009B3F, tile = 214 },
            [11] = { bank = 6, paletteNumber = 4, startAddr = 0x009B43, tile = 188 },
            [12] = { bank = 6, paletteNumber = 4, startAddr = 0x009B47, tile = 190 },
            [13] = { bank = 6, paletteNumber = 4, startAddr = 0x009B4B, tile = 240 },
            [14] = { bank = 6, paletteNumber = 4, startAddr = 0x009B4F, tile = 242 },
            [15] = { bank = 6, paletteNumber = 2, startAddr = 0x009B1F, tile = 202 },
            [16] = { bank = 6, paletteNumber = 4, startAddr = 0x009B53, tile = 244 },
            [17] = { bank = 6, paletteNumber = 2, startAddr = 0x009B17, tile = 192 },
            [18] = { bank = 6, paletteNumber = 4, startAddr = 0x009B57, tile = 246 },
            [19] = { bank = 6, paletteNumber = 1, startAddr = 0x009C12, tile = 198 },
            [20] = { bank = 6, paletteNumber = 1, startAddr = 0x009C1A, tile = 186 },
            [21] = { bank = 6, paletteNumber = 1, startAddr = 0x009B6E, tile = 222 },
            [22] = { bank = 6, paletteNumber = 2, startAddr = 0x009B72, tile = 196 },
            [23] = { bank = 6, paletteNumber = 2, startAddr = 0x009B1B, tile = 200 },
            [24] = { bank = 6, paletteNumber = 3, startAddr = 0x009B07, tile = 226 },
            [25] = { bank = 6, paletteNumber = 3, startAddr = 0x009B0F, tile = 230 },
            [26] = { bank = 6, paletteNumber = 3, startAddr = 0x009B03, tile = 224 }
          },
          kind = "sprite",
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
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 1,
      scrollRow = 5,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "Cutscene 1 - Bill",
      visibleCols = 18,
      visibleRows = 18,
      x = 189,
      y = 55,
      z = 110,
      zoom = 1
    },
    [12] = {
      activePalette = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_1",
      kind = "rom_palette",
      minimized = false,
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
      x = 528,
      y = 142,
      z = 120,
      zoom = 1
    },
    [13] = {
      activeLayer = 2,
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
          mode = "8x8",
          name = "Layer 1",
          nametableEndAddr = 0x01255A,
          nametableStartAddr = 0x012493,
          noOverflowSupported = false,
          opacity = 1,
          paletteData = {
            winId = "rom_palette_4"
          },
          patternTable = {
            ranges = {
              [1] = {
                bank = 16,
                page = 1,
                tileRange = {
                  from = 128,
                  to = 191
                }
              },
              [2] = {
                bank = 6,
                page = 1,
                tileRange = {
                  from = 64,
                  to = 255
                }
              }
            }
          },
          userDefinedAttrs = "000000000000000000000000000000000000551000000000004455110000000000a4aa2200000000008aaa220000000000000000000000000000000000000000"
        },
        [2] = {
          items = {
            [1] = { bank = 6, paletteNumber = 3, startAddr = 0x00A2DE, tile = 238 },
            [2] = { bank = 6, paletteNumber = 3, startAddr = 0x00A2E6, tile = 178 },
            [3] = { bank = 6, paletteNumber = 3, startAddr = 0x00A2EA, tile = 180 },
            [4] = { bank = 6, paletteNumber = 3, startAddr = 0x00A2F2, tile = 184 },
            [5] = { bank = 6, paletteNumber = 3, startAddr = 0x00A2EE, tile = 182 },
            [6] = { bank = 6, paletteNumber = 1, startAddr = 0x009B23, tile = 216 },
            [7] = { bank = 6, paletteNumber = 1, startAddr = 0x009B27, tile = 218 },
            [8] = { bank = 6, paletteNumber = 2, startAddr = 0x009B2B, tile = 204 },
            [9] = { bank = 6, paletteNumber = 2, startAddr = 0x009B2F, tile = 206 },
            [10] = { bank = 6, paletteNumber = 2, startAddr = 0x009B33, tile = 208 },
            [11] = { bank = 6, paletteNumber = 2, startAddr = 0x009B37, tile = 210 },
            [12] = { bank = 6, paletteNumber = 2, startAddr = 0x009B3B, tile = 212 },
            [13] = { bank = 6, paletteNumber = 2, startAddr = 0x009B3F, tile = 214 },
            [14] = { bank = 6, paletteNumber = 4, startAddr = 0x009B43, tile = 188 },
            [15] = { bank = 6, paletteNumber = 4, startAddr = 0x009B47, tile = 190 },
            [16] = { bank = 6, paletteNumber = 4, startAddr = 0x009B4B, tile = 240 },
            [17] = { bank = 6, paletteNumber = 4, startAddr = 0x009B4F, tile = 242 },
            [18] = { bank = 6, paletteNumber = 2, startAddr = 0x009B1F, tile = 202 },
            [19] = { bank = 6, paletteNumber = 4, startAddr = 0x009B53, tile = 244 },
            [20] = { bank = 6, paletteNumber = 2, startAddr = 0x009B17, tile = 192 },
            [21] = { bank = 6, paletteNumber = 4, startAddr = 0x009B57, tile = 246 },
            [22] = { bank = 6, paletteNumber = 1, startAddr = 0x009C12, tile = 198 },
            [23] = { bank = 6, paletteNumber = 1, startAddr = 0x009C1A, tile = 186 },
            [24] = { bank = 6, paletteNumber = 1, startAddr = 0x009B6E, tile = 222 },
            [25] = { bank = 6, paletteNumber = 2, startAddr = 0x009B72, tile = 196 },
            [26] = { bank = 6, paletteNumber = 2, startAddr = 0x009B1B, tile = 200 },
            [27] = { bank = 6, paletteNumber = 3, startAddr = 0x00A2E2, tile = 176 }
          },
          kind = "sprite",
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
      nonActiveLayerOpacity = 1,
      rows = 30,
      scrollCol = 0,
      scrollRow = 7,
      showGrid = "chess",
      showSpriteOriginGuides = false,
      title = "Cutscene 1 - Lance",
      visibleCols = 18,
      visibleRows = 18,
      x = 345,
      y = 47,
      z = 130,
      zoom = 1
    },
    [14] = {
      activePalette = false,
      collapsed = true,
      cols = 4,
      compactView = true,
      id = "rom_palette_4",
      kind = "rom_palette",
      minimized = false,
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
      z = 140,
      zoom = 1
    },
    [15] = {
      activePalette = false,
      collapsed = false,
      cols = 4,
      compactView = true,
      id = "rom_palette_3",
      kind = "rom_palette",
      minimized = false,
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
      z = 150,
      zoom = 1
    },
    [16] = {
      activePalette = false,
      collapsed = false,
      cols = 4,
      compactView = true,
      id = "rom_palette_2",
      kind = "rom_palette",
      minimized = false,
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
      x = 216,
      y = 241,
      z = 160,
      zoom = 1
    }
  }
}
