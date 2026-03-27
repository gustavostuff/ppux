-- Keys whose numeric values should be written as hex, e.g. 0x00F9A8
local HEX_NUMBER_KEYS = {
  nametableEndAddr   = true,
  nametableStartAddr = true,
  startAddr          = true,
}

-- Parent keys whose numeric descendants should be written as hex (e.g., ROM addresses)
local HEX_NUMBER_CHILD_OF = {
  romColors = true,
  romPatches = true,
}

-- Parent table keys whose *elements* should be one-line tables:
--   items = {
--     [1] = { attr = 0, bank = 4, startAddr = 0x00F9A8, tile = 252, x = 208, y = 172 },
--     ...
--   }
local SINGLELINE_CHILD_OF = {
  items = true,
  tileSwaps = true,
}

local function serialize_lua_table(t, indent)
  indent = indent or 0
  local out = {}

  local function ind(n) return string.rep("  ", n) end

  -- Append a scalar value (number/string/other), respecting hex rules
  local function append_scalar(v, keyName, hexContext, parentKeyName)
    local tv = type(v)
    if tv == "number" and (hexContext or (keyName and HEX_NUMBER_KEYS[keyName])) then
      local width = 6
      if keyName == "value" or parentKeyName == "values" then
        width = 2
      end
      table.insert(out, string.format("0x%0" .. width .. "X", v))
    elseif tv == "string" then
      table.insert(out, string.format("%q", v))
    else
      table.insert(out, tostring(v))
    end
  end

  local function key_comparator(a, b)
    local ta, tb = type(a), type(b)
    if ta == tb then
      if ta == "number" then
        return a < b
      else
        return tostring(a) < tostring(b)
      end
    else
      return ta < tb  -- e.g., "number" < "string"
    end
  end

  local function ser(v, n, keyName, parentKeyName, hexContext)
    local tv = type(v)

    if tv == "table" then
      -- Inherit hex formatting if this table or its parent is marked
      local childHexContext = hexContext
      if HEX_NUMBER_CHILD_OF[keyName] or HEX_NUMBER_CHILD_OF[parentKeyName] then
        childHexContext = true
      end

      -- Collect and sort keys (numbers numerically, others alphabetically, numbers before strings if mixed)
      local keys = {}
      for k in pairs(v) do
        table.insert(keys, k)
      end
      table.sort(keys, key_comparator)

      -- One-line child table inside certain parents (e.g. items)
      if parentKeyName and SINGLELINE_CHILD_OF[parentKeyName] then
        table.insert(out, "{ ")

        local firstField = true
        for _, k in ipairs(keys) do
          if not firstField then
            table.insert(out, ", ")
          end
          firstField = false

          local fieldKey
          if type(k) == "number" then
            fieldKey = "[" .. k .. "]"
          elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
            fieldKey = k
          else
            fieldKey = string.format("[%q]", tostring(k))
          end

          table.insert(out, fieldKey .. " = ")
          local fv = v[k]
          local fvt = type(fv)
          if fvt == "table" then
            -- Nested table inside a one-line element: fallback to normal table rules
            ser(fv, n, k, k, childHexContext)
          else
            append_scalar(fv, k, childHexContext, keyName)
          end
        end

        table.insert(out, " }")
        return
      end

      -- Normal multi-line table
      table.insert(out, "{")
      local first = true
      for _, k in ipairs(keys) do
        if not first then table.insert(out, ",") end
        first = false
        table.insert(out, "\n" .. ind(n + 1))

        local keyStr
        if type(k) == "number" then
          keyStr = "[" .. k .. "]"
        elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
          keyStr = k
        else
          keyStr = string.format("[%q]", tostring(k))
        end

        table.insert(out, keyStr .. " = ")
        ser(v[k], n + 1, k, keyName, childHexContext)  -- keyName = this key; parentKeyName = table's key
      end
      table.insert(out, "\n" .. ind(n) .. "}")
    else
      append_scalar(v, keyName, hexContext, parentKeyName)
    end
  end

  ser(t, indent, nil, nil, false)
  return "return " .. table.concat(out) .. "\n"
end

local function deepcopy(v)
  local tv = type(v)
  if tv ~= "table" then return v end
  local t = {}
  for k, vv in pairs(v) do t[k] = deepcopy(vv) end
  return t
end

return {
  serialize_lua_table = serialize_lua_table,
  deepcopy = deepcopy
}
