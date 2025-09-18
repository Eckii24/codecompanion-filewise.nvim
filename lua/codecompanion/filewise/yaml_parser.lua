--=============================================================================
-- filewise/yaml_parser – Simple YAML parser for frontmatter
--=============================================================================

local M = {}

local function trim(s)
  if not s then return s end
  return s:match('^%s*(.-)%s*$')
end

local function unquote(s)
  if not s then return s end
  return s:match('^"(.-)"$') or s:match("^'(.-)'$") or s
end

--- Simple YAML parser for basic key-value frontmatter
--- Supports:
---  - simple key: value pairs
---  - inline lists: key: [a, b, c]
---  - dash lists:
---      key:
---        - a
---        - b
---  - block scalars using | or >
--- @param yaml_text string The YAML content to parse
--- @return table|nil Parsed YAML as a table, or nil if invalid
function M.parse(yaml_text)
  if not yaml_text or yaml_text == "" then
    return nil
  end

  local result = {}
  local lines = {}
  for l in yaml_text:gmatch('[^\r\n]+') do
    table.insert(lines, l)
  end

  local i = 1
  while i <= #lines do
    local raw = lines[i]
    local line = trim(raw)
    -- skip empty and comment lines
    if line == '' or line:match('^#') then
      i = i + 1
    else
      local key, value = line:match('^([%w_%-]+)%s*:%s*(.*)$')
      if key then
        -- empty value -> might be a dash list or block following
        if value == '' then
          -- check for dash list on following lines
          local items = {}
          local j = i + 1
          while j <= #lines do
            local nxt = lines[j]
            if nxt:match('^%s*%-+%s+') then
              local item = nxt:match('^%s*%-+%s+(.*)$')
              item = trim(item)
              item = unquote(item)
              table.insert(items, item)
              j = j + 1
            elseif nxt:match('^%s*$') then
              j = j + 1
            else
              break
            end
          end
          if #items > 0 then
            result[key] = items
            i = j
          else
            -- nothing special; store empty string
            result[key] = ''
            i = i + 1
          end
        else
          -- inline list? e.g. [a, b, c]
          local inline = value:match('^%[(.*)%]$')
          if inline then
            local items = {}
            for part in inline:gmatch('[^,]+') do
              local v = trim(part)
              v = unquote(v)
              table.insert(items, v)
            end
            result[key] = items
            i = i + 1
          elseif value == '|' or value == '>' then
            -- block scalar: collect following indented lines (start with whitespace)
            local j = i + 1
            local buf = {}
            while j <= #lines do
              local nxt = lines[j]
              if nxt:match('^%s+') then
                table.insert(buf, trim(nxt))
                j = j + 1
              else
                break
              end
            end
            result[key] = table.concat(buf, '\n')
            i = j
          else
            local v = trim(value)
            v = unquote(v)
            result[key] = v
            i = i + 1
          end
        end
      else
        -- not a key line; ignore
        i = i + 1
      end
    end
  end

  if next(result) == nil then
    return nil
  end
  return result
end

return M