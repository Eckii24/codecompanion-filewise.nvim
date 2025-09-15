--=============================================================================
-- custom_instructions – CodeCompanion extension for custom instruction files
--=============================================================================

local M = {}

local Path = require('plenary.path')
local scan = require('plenary.scandir')

local cc_slash_file = require('codecompanion.strategies.chat.slash_commands.file')

local uv = vim.loop

--- @class CustomInstructionsConfig
--- @field enabled boolean Whether the extension is enabled
--- @field simple string[] List of simple instruction file/globs
--- @field conditional string[] List of conditional instruction file/globs

--- @type CustomInstructionsConfig
M.config = {
  enabled = true,
  simple = {
    '.ai/rules.md', '.ai/*.rules.md',
    '.rules',
    '.goosehints',
    '.cursorrules',
    '.windsurfrules',
    '.clinerules',
    '.github/copilot-instructions.md',
    'AGENT.md',
    'AGENTS.md',
    'CLAUDE.md',
    '.codecompanionrules',
  },
  conditional = {
    '.github/instructions/*.instructions.md',
  },
  triggers = {
    user_events = { "CodeCompanionChatCreated", "CodeCompanionChatSubmitted" },
    variable_buffer = false,
    slash_file = true,
    slash_buffer = true,
  },
  root_markers = { '.git', '.github' },
}

--- Mapping from glob pattern to list of instruction file paths (simple and conditional)
--- @type table<string, string[]>
local apply_map = {}

--- Find project root directory given a file path
--- @param path? string Path to a file or directory (cwd by default)
--- @return string? Project root directory (absolute path) or nil if not found
local function find_project_root(path)
  local cwd = vim.fn.getcwd()
  local dir = Path:new(path or cwd)
  if dir:is_file() then dir = dir:parent() end
  local markers = M.config.root_markers or { '.git' }
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

--- Expand globs to files from project root.
--- @param globs string[] List of glob patterns
--- @param base_path string|nil Optional base path to determine project root
--- @return string[] List of resolved file paths
local function expand_globs(globs, base_path)
  local results = {}
  local project_root = find_project_root(base_path)
  for _, g in ipairs(globs) do
    local matches = vim.fn.glob(project_root .. '/' .. g, false, true)
    for _, m in ipairs(matches) do
      table.insert(results, vim.fn.fnamemodify(m, ':p'))
    end
  end
  return results
end

--- Parse YAML frontmatter from a markdown file.
--- @param path string Path to the markdown file
--- @return table|nil Parsed YAML frontmatter as a table.
local function parse_frontmatter(path)
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
  local ok, lyaml = pcall(require, 'lyaml')
  if not ok then
    vim.notify('[CustomInstructions] \'lyaml\' module not found', vim.log.levels.WARN)
    return nil
  end
  local ok2, res = pcall(lyaml.load, table.concat(lines, '\n'))
  if ok2 and type(res) == 'table' then
    return res
  end
  return nil
end

--- Split comma-separated globs into a list.
--- @param str string Comma-separated globs
--- @return string[] List of trimmed glob patterns
local function split_globs(str)
  local out = {}
  for g in str:gmatch('[^,]+') do
    table.insert(out, vim.trim(g))
  end
  return out
end

--- Build mapping of instruction files from config.
--- Populates apply_map and instruction_files.
local function build_mapping()
  if not M.config.enabled then return end
  -- Reset always included files
  apply_map = { ['**'] = {} }
    for _, path in ipairs(expand_globs(M.config.simple)) do
      table.insert(apply_map['**'], path)
    end
    -- Add conditional files to their respective globs
    for _, path in ipairs(expand_globs(M.config.conditional)) do
      local fm = parse_frontmatter(path)
      if fm and fm.applyTo then
        for _, g in ipairs(split_globs(fm.applyTo)) do
          apply_map[g] = apply_map[g] or {}
          table.insert(apply_map[g], path)
        end
      end
    end
end

--- Match file path against a Unix-style glob pattern.
--- @param path string File path
--- @param glob string Glob pattern
--- @return boolean True if path matches glob
local function matches_glob(path, glob)
  if vim.regex(vim.fn.glob2regpat(glob)):match_str(path) then
    return true
  end
end

---
-- Add a file to the chat context using the /file slash command.
-- Calls the CodeCompanion file slash command to add the given file to the specified chat context.
-- @param chat table The chat object to add the file to
-- @param file string The file path to add to the context
local function slash_file(chat, file)
  --cc_slash_file.new({ Chat = chat }):output({ path = file })
  chat.context:add({
    id = '<file>' .. file .. '</file>',
    path = file,
    source = "codecompanion.strategies.chat.slash_commands.file",
  })
end

---
-- Add relevant instruction files to the context for a given buffer.
-- @param bufnr integer Buffer number
function M.sync_context(bufnr)
  if not M.config.enabled then return end
  -- Get current chat
  local chat = require('codecompanion.strategies.chat').buf_get_chat(bufnr)
  if not chat then return end
  -- Get project root
  local project_root = find_project_root()
  if not project_root then
    vim.notify('[CustomInstructions] Are you inside a project workspace?', vim.log.levels.WARN)
    return
  end
  -- Gather current local/project context
  local ctx = {}
  for _, c in ipairs(chat.context_items or {}) do
    local file = c.path
    if not file and c.id then
      file = c.id:match('^<file>(.-)</file>$') or c.id:match('^<buf>(.-)</buf>$')
    end
    if file then
      local path = Path:new(Path:new(file):absolute())
      if vim.startswith(path.filename, project_root) then
        table.insert(ctx, path:make_relative(project_root))
      end
    end
  end
  -- Gather instruction files to be added to the context
  local to_add = {}
  for _, c in ipairs(ctx) do
    for glob, files in pairs(apply_map) do
      if glob == '**' or matches_glob(c, glob) then
        for _, instr in ipairs(files) do
          local rel = Path:new(instr):make_relative(project_root)
          to_add[rel] = not vim.tbl_contains(ctx, rel)
        end
      end
    end
  end
  -- Finally add files
  for file, add in pairs(to_add) do
    if add then slash_file(chat, file) end
  end
end

--- Setup the CustomInstructions extension.
--- Initializes config, builds mapping, and sets up user commands and hooks.
--- @param opts table|nil Optional configuration overrides
function M.setup(opts)
  if opts then M.config = vim.tbl_deep_extend('force', M.config, opts) end

  -- Build mapping between files/globs and instruction files
  build_mapping()

  -- User commands
  vim.api.nvim_create_user_command('CustomInstructionsReload', build_mapping, {desc='Refresh custom instruction file mapping'})
  vim.api.nvim_create_user_command('CustomInstructionsContextSync', function(opts)
    M.sync_context(opts.args ~= '' and tonumber(opts.args) or vim.api.nvim_get_current_buf())
  end, {desc='Sync custom instructions to context', nargs='?'})

  -- Context sync on events
  local grp = vim.api.nvim_create_augroup("CodeCompanionCustomInstructions", { clear = true })
  for _, event in ipairs(M.config.triggers.user_events) do
    vim.api.nvim_create_autocmd("User", {
      group = grp,
      pattern = event,
      callback = function() M.sync_context(vim.api.nvim_get_current_buf()) end,
    })
  end

  -- Patch #buffer variable to trigger context injection
  if M.config.triggers.variable_buffer then
    local ok, variable_buffer = pcall(require, 'codecompanion.strategies.chat.variables.buffer')
    if ok and variable_buffer and variable_buffer.output then
      local orig_output = variable_buffer.output
      variable_buffer.output = function(self, ...)
        orig_output(self, ...)
        vim.schedule(function()
          if self.Chat and self.Chat.bufnr then
            M.sync_context(self.Chat.bufnr)
          end
        end)
      end
      vim.notify('[CustomInstructions] Patched #buffer variable')
    end
  end

  -- Patch /file slash command to trigger context injection
  if M.config.triggers.slash_file then
    local ok, slash_file = pcall(require, 'codecompanion.strategies.chat.slash_commands.file')
    if ok and slash_file and slash_file.output then
      local orig_output = slash_file.output
      slash_file.output = function(self, ...)
        orig_output(self, ...)
        vim.schedule(function()
          if self.Chat and self.Chat.bufnr then
            M.sync_context(self.Chat.bufnr)
          end
        end)
      end
      vim.notify('[CustomInstructions] Patched /file slash command')
    end
  end

  -- Patch /buffer slash command to trigger context injection
  if M.config.triggers.slash_buffer then
    local ok, slash_buffer = pcall(require, 'codecompanion.strategies.chat.slash_commands.buffer')
    if ok and slash_buffer and slash_buffer.output then
      local orig_output = slash_buffer.output
      slash_buffer.output = function(self, ...)
        orig_output(self, ...)
        vim.schedule(function()
          if self.Chat and self.Chat.bufnr then
            M.sync_context(self.Chat.bufnr)
          end
        end)
      end
      vim.notify('[CustomInstructions] Patched /buffer slash command')
    end
  end

end

return M
