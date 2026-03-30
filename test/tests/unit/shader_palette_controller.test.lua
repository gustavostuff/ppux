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

    it("resolves linked global palette window codes by winId", function()
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
    
    it("falls back to global palette when layer has no paletteData", function()
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
  
end)
