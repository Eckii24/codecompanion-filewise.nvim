--=============================================================================
-- filewise/frontmatter – Utilities for parsing YAML frontmatter from markdown
--=============================================================================

local lyaml = require 'lyaml'

local M = {}

--- Parses YAML frontmatter from a markdown file and returns it as a Lua table.
---@param path string Path to the markdown file
---@return table|nil Parsed YAML frontmatter as a table, or nil if not found or invalid
function M.parse_frontmatter(path)
  local lines = {}
  local in_frontmatter = false
  for l in io.lines(path) do
    if l:match('^%-%-%-') then
      if not in_frontmatter then
        in_frontmatter = true
      else
        break
      end
    elseif in_frontmatter then
      table.insert(lines, l)
    end
  end
  if #lines == 0 then return nil end
  local ok2, res = pcall(lyaml.load, table.concat(lines, '\n'))
  if ok2 and type(res) == 'table' then
    return res
  end
  return nil
end

return M
