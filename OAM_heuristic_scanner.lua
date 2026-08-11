-- Note: This uses Lua 5.3 bitwise operators (&). 
-- If using Lua 5.1/LuaJIT, replace (attr & 0x1C) with bit.band(attr, 0x1C)

function scan_for_oam_blocks(rom_data)
    local found_offsets = {}
    
    -- Iterate through the ROM, stopping 8 bytes before the end 
    -- to ensure we can always read two consecutive sprites safely.
    for i = 1, #rom_data - 7 do
        -- Sprite 1
        local y1    = rom_data[i]
        local tile1 = rom_data[i + 1]
        local attr1 = rom_data[i + 2]
        local x1    = rom_data[i + 3]
        
        -- Sprite 2
        local y2    = rom_data[i + 4]
        local tile2 = rom_data[i + 5]
        local attr2 = rom_data[i + 6]
        local x2    = rom_data[i + 7]
        
        -- Heuristic 1: Valid Attribute Bytes (bits 2, 3, and 4 must be 0)
        if (attr1 & 0x1C) == 0 and (attr2 & 0x1C) == 0 then
            
            -- Heuristic 2: Sprites are physically aligned (sharing X or Y)
            if x1 == x2 or y1 == y2 then
                
                -- Sequence found! Store the offset (0-indexed for hex editors)
                table.insert(found_offsets, {
                    offset = i - 1,
                    aligned_horizontally = (y1 == y2),
                    aligned_vertically = (x1 == x2)
                })
            end
        end
    end
    
    return found_offsets
end

-- Example Usage:
-- local rom = read_file_as_byte_array("game.nes")
-- local oam_locations = scan_for_oam_blocks(rom)
-- for _, loc in ipairs(oam_locations) do
--     print(string.format("Potential OAM at offset 0x%X", loc.offset))
-- end
