local Path = require('plenary.path')

local M = {}

--- Find project root directory given a file path and root markers.
---@param markers string[] List of marker files or directories
---@param path? string Path to a file or directory (cwd by default)
---@return string|nil Project root directory (absolute path) or nil if not found
function M.find_project_root(markers, path)
  local cwd = vim.fn.getcwd()
  local dir = Path:new(path or cwd)
  if dir:is_file() then dir = dir:parent() end
  while dir and dir:absolute() ~= '/' do
    for _, marker in ipairs(markers) do
      if (dir / marker):exists() then
        return dir:absolute()
      end
    end
    dir = dir:parent()
    if not dir then break end
  end
  return nil
end

return M
