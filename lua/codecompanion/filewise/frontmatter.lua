--=============================================================================
-- filewise/frontmatter – Utilities for parsing YAML frontmatter from markdown
--=============================================================================

local M = {}

---@class FrontmatterConfig
---@field yaml_parser? fun(yaml_text: string): table|nil Custom YAML parser function

--- Configuration for the frontmatter module
---@type FrontmatterConfig
M.config = {
  yaml_parser = nil, -- Default to lyaml
}

--- Setup the frontmatter module with custom configuration
---@param opts FrontmatterConfig|nil Configuration options
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend('force', M.config, opts)
  end
end

--- Get the YAML parser function to use
---@return fun(yaml_text: string): table|nil
local function get_yaml_parser()
  if M.config.yaml_parser then
    return M.config.yaml_parser
  else
    -- Default to lyaml
    local ok, lyaml = pcall(require, 'lyaml')
    if ok then
      return lyaml.load
    else
      -- Fallback to custom parser if lyaml is not available
      local yaml_parser = require 'codecompanion.filewise.yaml_parser'
      return yaml_parser.parse
    end
  end
end

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
  
  local parser = get_yaml_parser()
  local ok, fm = pcall(parser, table.concat(frontmatter, '\n'))
  if ok and type(fm) == 'table' then
    return fm, body
  end
  return nil
end

return M
