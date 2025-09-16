-- TODO move available tools to a second user prompt
local M = {}

local Path = require("plenary.path")
local scan = require("plenary.scandir")
local frontmatter = require("codecompanion.filewise.frontmatter")
local utils = require("codecompanion.filewise.utils")

---@class CustomModesConfig
---@field enabled boolean Whether the extension is enabled
---@field mode_dirs string[] List of directories to scan for mode files (paths are absolute or relative to workspace)
---@field model_map table<string, string> Mapping from Copilot model names to CodeCompanion model names
---@field tool_map table<string, string> Mapping from Copilot tool names to CodeCompanion tool names
---@field format_content fun(line:string): string Function to format the prompt content (line-wise)
---@field root_markers string[] List of root marker filenames to identify project root
M.config = {
  enabled = true,
  mode_dirs = {
    ".github/chatmodes",
    (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')) .. '/codecompanion/filewise/chatmodes',
  },
  model_map = {},
  tool_map = {},
  format_content = function(l) return l end,
  root_markers = { '.git', '.github' },
}

---Format tools for display in prompt content.
---@param tools string[]|nil List of tools
---@return string Formatted string of tools
local function format_tools(tools)
  local tools = vim.tbl_map(function(t) return M.config.tool_map[t] or ('@{' .. t .. '}') end, tools or {})
  if #tools > 0 then
    return '\n\n**Available tools:** ' .. table.concat(tools, ", ") .. '\n\n'
  else
    return ''
  end
end

---Format the prompt body applying variable and user-defined substitutions.
---@param ctx table|nil CodeCompanion context
---@param file string Name of the mode file
---@param body string[] List of lines from mode body
---@return string Fromatted prompt body
local function format_body(ctx, file, body)
  -- Workspace variables: ${workspaceFolder}, ${workspaceFolderBasename}
  local workspace_folder = utils.find_project_root(M.config.root_markers) or vim.fn.getcwd()
  local workspace_folder_basename = workspace_folder:gsub('^.+/',''):gsub('/+$','')
  -- File context variables: ${file}, ${fileBasename}, ${fileDirname}, ${fileBasenameNoExtension}
  -- TODO This might not be the name of the prompt file but the name of the file in the active buffer.
  local file_basename = file:gsub('^.+/','')
  local file_basename_noext = file_basename:gsub('%..-$','')
  local file_dirname = Path:new(file):parent():absolute():gsub('^.+/','')
  -- Input variables: ${input:variableName}, ${input:variableName:placeholder} (pass values to the prompt from the chat input field)
  local body = vim.tbl_map(function(l)
    return l:gsub('%${workspaceFolder}', workspace_folder)
            :gsub('%${workspaceFolderBasename}', workspace_folder_basename)
            :gsub('%${file}', file)
            :gsub('%${fileBasename}', file_basename)
            :gsub('%${fileBasenameNoExtension}', file_basename_noext)
            :gsub('%${fileDirname}', file_dirname)
            :gsub('%${input:([%w-_]+):?([^}]*)}', function(var, default)
              -- TODO: use vim.ui.input when it becomes synchronous
              return vim.fn.input('Value for ' .. var .. ': ', default)
            end)
  end, body)
  -- User format function
  body = vim.tbl_map(M.config.format_content, body)
  -- Selection variables: ${selection}, ${selectedText}
  local selection = {}
  if ctx and ctx.is_visual and #ctx.lines > 0 then
    table.insert(selection, '')
    table.insert(selection, '```' .. ctx.filetype)
    vim.list_extend(selection, ctx.lines)
    table.insert(selection, '```')
    table.insert(selection, '')
  else
    -- TODO: query for register?
    selection = vim.fn.getreg('*', 1, true)
  end
  selection = table.concat(selection, '\n')
  body = table.concat(body, '\n')
    :gsub('%${selection}', selection)
    :gsub('%${selectedText}', selection)
  return body
end

---Returns a prettified prompt name with spaces and capitalization.
---@param str string The original prompt name
---@return string Prettified prompt name
local function prettify_name(str)
  return str:gsub('[-_]', ' ')              -- Replace - and _ with spaces
            :gsub("%f[%a]%l", string.upper) -- Capitalize first letter of each word
end

---Create a CodeCompanion prompt from a Copilot mode file.
---@param short_name string The prompt short name
---@param file string Path to the mode file
---@return str The prompt name
---@return table The custom prompt
local function make_prompt(short_name, file)
  local fm, body = frontmatter.parse(file, true)
  local name = fm.title or prettify_name(short_name)
  return name, {
    strategy = "chat",
    description = fm.description or ("Custom prompt from " .. short_name .. ".chatmode.md"),
    opts = {
      short_name = short_name,
      intro_message = fm.title,
      ignore_system_prompt = true,
      adapter = {
        model = fm.model and M.config.model_map[fm.model] or fm.model,
      },
      stop_context_insertion = true,
    },
    prompts = {
      {
        role = "system",
        content = function(ctx)
          return format_body(ctx, file, body)
        end,
      },
      {
        role = "user",
        content = function(ctx)
          return format_tools(fm.tools)
        end,
        condition = function(ctx)
          return fm.tools and #fm.tools > 0
        end,
      }
    }
  }
end

---Normalize mode directories
---@return string[] List of existing mode directories (absolute paths)
local function gather_mode_dirs()
  local dirs = {}
  local project_root = Path:new(utils.find_project_root(M.config.root_markers) or vim.fn.getcwd())
  for _, d in ipairs(M.config.mode_dirs) do
    local path = Path:new(d)
    if not path:is_absolute() then
      path = project_root / path
    end
    if path:exists() then
      table.insert(dirs, path:absolute())
    end
  end
  return dirs
end

---Setup the CustomModes extension.
---@param opts table|nil Optional configuration overrides
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if not M.config.enabled then return end
  local prompt_library = require("codecompanion.config").config.prompt_library
  local files = scan.scan_dir(gather_mode_dirs(), { search_pattern = "%.chatmode%.md$" })
  for _, file in ipairs(files) do
    local short_name = file:gsub('^.+/',''):gsub('%.chatmode.md$', '')
    local name, prompt = make_prompt(short_name, file)
    prompt_library[name] = prompt
  end
end

return M
