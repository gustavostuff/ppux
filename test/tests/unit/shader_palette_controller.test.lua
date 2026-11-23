-- shader_palette_controller.test.lua
-- Unit tests for managers/shader_palette_controller.lua

local ShaderPaletteController = require("controllers.palette.shader_palette_controller")

describe("shader_palette_controller.lua", function()
  
  describe("resolveLayerPaletteCodes", function()
    it("resolves palette codes from layer paletteData", function()
      local layer = {
        paletteData = {
          items = {
            {"0F", "30", "28", "16"},
            {"0F", "30", "06", "16"},
            {"0F", "10", "27", "16"},
            {"0F", "30", "36", "26"},
          }
        }
      }
      
      local codes = ShaderPaletteController.resolveLayerPaletteCodes(layer, 1, nil)
      expect(codes).toEqual({"0F", "30", "28", "16"})
      
      codes = ShaderPaletteController.resolveLayerPaletteCodes(layer, 2, nil)
      expect(codes).toEqual({"0F", "30", "06", "16"})
    end)
    
    it("returns nil for invalid palette number", function()
      local layer = {
        paletteData = {
          items = {
            {"0F", "30", "28", "16"},
          }
        }
      }
      
      expect(ShaderPaletteController.resolveLayerPaletteCodes(layer, 5, nil)).toBeNil()
      expect(ShaderPaletteController.resolveLayerPaletteCodes(layer, 0, nil)).toBeNil()
    end)
    
    it("returns nil for layer without paletteData", function()
      local layer = {}
      expect(ShaderPaletteController.resolveLayerPaletteCodes(layer, 1, nil)).toBeNil()
    end)
    
    it("returns nil for missing items", function()
      local layer = {
        paletteData = {}
      }
      expect(ShaderPaletteController.resolveLayerPaletteCodes(layer, 1, nil)).toBeNil()
    end)

    it("resolves linked generic palette window codes by winId", function()
      local previousCtx = rawget(_G, "ctx")
      _G.ctx = {
        wm = function()
          return {
            findWindowById = function(_, id)
              if id == "palette_1" then
                return {
                  kind = "palette",
                  codes2D = {
                    [0] = { [0] = "0F", [1] = "30", [2] = "28", [3] = "16" },
                  },
                }
              end
              return nil
            end,
          }
        end,
      }

      local layer = {
        paletteData = {
          winId = "palette_1",
        }
      }

      local codes = ShaderPaletteController.resolveLayerPaletteCodes(layer, 2, nil)
      _G.ctx = previousCtx

      expect(codes).toEqual({"0F", "30", "28", "16"})
    end)
  end)

  describe("nametableSubpaletteCodes", function()
    local function restoreCodes(previous)
      ShaderPaletteController.setCodes(previous)
    end

    local function copyCodes()
      local current = ShaderPaletteController.getCodes()
      return { current[1], current[2], current[3], current[4] }
    end

    it("uses the active generic palette for every slot when the layer is unlinked", function()
      local previous = copyCodes()
      ShaderPaletteController.setCodes({ "11", "22", "33", "44" })

      local codes = ShaderPaletteController.nametableSubpaletteCodes({}, 4, nil)
      restoreCodes(previous)

      expect(codes).toEqual({ "11", "22", "33", "44" })
    end)

    it("follows the active generic palette when the link is a generic palette window", function()
      local previousCtx = rawget(_G, "ctx")
      local previous = copyCodes()
      _G.ctx = {
        wm = function()
          return {
            findWindowById = function(_, id)
              if id == "palette_1" then
                return {
                  kind = "palette",
                  codes2D = {
                    [0] = { [0] = "0F", [1] = "30", [2] = "28", [3] = "16" },
                  },
                }
              end
              return nil
            end,
          }
        end,
      }
      ShaderPaletteController.setCodes({ "01", "02", "03", "04" })

      local codes = ShaderPaletteController.nametableSubpaletteCodes({
        paletteData = { winId = "palette_1" },
      }, 2, nil)

      _G.ctx = previousCtx
      restoreCodes(previous)

      expect(codes).toEqual({ "01", "02", "03", "04" })
    end)

    it("keeps the linked ROM palette row for that attribute slot", function()
      local previousCtx = rawget(_G, "ctx")
      _G.ctx = {
        wm = function()
          return {
            findWindowById = function(_, id)
              if id == "rom_palette_1" then
                return {
                  kind = "rom_palette",
                  codes2D = {
                    [0] = { [0] = "0F", [1] = "30", [2] = "28", [3] = "16" },
                    [1] = { [0] = "0F", [1] = "11", [2] = "22", [3] = "33" },
                    [2] = { [0] = "0F", [1] = "21", [2] = "22", [3] = "23" },
                    [3] = { [0] = "0F", [1] = "31", [2] = "32", [3] = "33" },
                  },
                }
              end
              return nil
            end,
          }
        end,
      }

      local codes = ShaderPaletteController.nametableSubpaletteCodes({
        paletteData = { winId = "rom_palette_1" },
      }, 3, nil)
      _G.ctx = previousCtx

      expect(codes).toEqual({ "0F", "21", "22", "23" })
    end)

    it("compiles the nametable index shaders", function()
      ShaderPaletteController.applyNametableIndexEncode(3)
      ShaderPaletteController.applyNametableLayerShader({
        paletteData = {
          items = {
            { "0F", "30", "28", "16" },
          },
        },
      }, nil, 0.5)
      ShaderPaletteController.releaseShader()
      expect(true).toBe(true)
    end)
  end)
  
  describe("getPaletteColors", function()
    it("returns all 4 colors from palette", function()
      local layer = {
        paletteData = {
          items = {
            {"0F", "30", "28", "16"},
          }
        }
      }
      
      local colors = ShaderPaletteController.getPaletteColors(layer, 1, nil)
      expect(colors).toBeTruthy()
      expect(#colors).toBe(4)
      -- Colors should be RGB arrays
      expect(type(colors[1])).toBe("table")
      expect(#colors[1]).toBe(3) -- r, g, b
    end)
    
    it("falls back to generic palette when layer has no paletteData", function()
      local layer = {}
      local colors = ShaderPaletteController.getPaletteColors(layer, 1, nil)
      expect(colors).toBeTruthy()
      expect(#colors).toBe(4)
    end)
  end)
  
  describe("getCodes", function()
    it("returns default palette codes", function()
      local codes = ShaderPaletteController.getCodes()
      expect(#codes).toBe(4)
      expect(type(codes[1])).toBe("string")
    end)
  end)

  describe("transparentZero", function()
    it("accepts opaque index-0 for BG sketch without error", function()
      -- CHR/sprite default stays transparentZero; sketch BG linked draw passes false.
      ShaderPaletteController.applyShader(true, nil, { "07", "17", "27", "37" }, 1.0)
      ShaderPaletteController.applyShader(
        true, nil, { "07", "17", "27", "37" }, 1.0, { transparentZero = false }
      )
      ShaderPaletteController.releaseShader()
      expect(true).toBe(true)
    end)
  end)
  
end)
