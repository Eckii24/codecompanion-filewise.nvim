--=============================================================================
-- filewise/frontmatter – Utilities for parsing YAML frontmatter from markdown
--=============================================================================

local lyaml = require 'lyaml'

local M = {}

--- Parses YAML frontmatter from a markdown file and returns it as a Lua table.
---@param path string Path to the markdown file
---@param rest boolean Whether to return the rest of the file as well.
---@return table|nil Parsed YAML frontmatter as a table, or nil if not found or invalid
---@return table The content lines of the file, except for the frontmatter.
function M.parse(path, rest)
  local in_frontmatter = false
  local after_frontmatter = false
  local frontmatter = {}
  local body = {}
  for l in io.lines(path) do
    if l:match('^%-%-%-') then
      if not in_frontmatter then
        in_frontmatter = true
      elseif not after_frontmatter then
        after_frontmatter = true
      else
        if rest then table.insert(body, l) else break end
      end
    elseif in_frontmatter and not after_frontmatter then
      table.insert(frontmatter, l)
    elseif after_frontmatter then
      if rest then table.insert(body, l) else break end
    end
  end
  local ok, fm = pcall(lyaml.load, table.concat(frontmatter, '\n'))
  if ok and type(fm) == 'table' then
    return fm, body
  end
  return nil
end

return M
