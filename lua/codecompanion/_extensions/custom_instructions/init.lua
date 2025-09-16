
local M = {}

local Path = require('plenary.path')
local scan = require('plenary.scandir')

local frontmatter = require('codecompanion.filewise.frontmatter')
local utils = require('codecompanion.filewise.utils')
local cc_slash_file = require('codecompanion.strategies.chat.slash_commands.file')


local uv = vim.loop

---@class CustomInstructionsTriggers
---@field user_events string[] List of user event names
---@field variable_buffer boolean Enable variable buffer trigger
---@field slash_file boolean Enable /file slash command trigger
---@field slash_buffer boolean Enable /buffer slash command trigger

---@class CustomInstructionsKeymaps
---@field sync_context string Normal-mode mapping to trigger context synchronization

---@class CustomInstructionsConfig
---@field enabled boolean Whether the extension is enabled
---@field simple string[] List of simple instruction file/globs
---@field conditional string[] List of conditional instruction file/globs
---@field triggers CustomInstructionsTriggers Trigger configuration
---@field keymaps CustomInstructionsKeymaps Keymaps configuration
---@field root_markers string[] List of project root marker files or directories

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
  keymaps = {
    sync_context = 'gi',
  },
  root_markers = { '.git', '.github' },
}

---Mapping from glob pattern to list of instruction file paths (simple and conditional)
---@type table<string, string[]>
local apply_map = {}

---Expand globs to files from project root.
---@param globs string[] List of glob patterns
---@param base_path string|nil Optional base path to determine project root
---@return string[] List of resolved file paths
local function expand_globs(globs, base_path)
  local results = {}
  local project_root = utils.find_project_root(M.config.root_markers, base_path)
  for _, g in ipairs(globs) do
    local matches = vim.fn.glob(project_root .. '/' .. g, false, true)
    for _, m in ipairs(matches) do
      table.insert(results, vim.fn.fnamemodify(m, ':p'))
    end
  end
  return results
end

---Split comma-separated globs into a list.
---@param str string Comma-separated globs
---@return string[] List of trimmed glob patterns
local function split_globs(str)
  local out = {}
  for g in str:gmatch('[^,]+') do
    table.insert(out, vim.trim(g))
  end
  return out
end

---Match file path against a Unix-style glob pattern.
---@param path string File path
---@param glob string Glob pattern
---@return boolean True if path matches glob
local function matches_glob(path, glob)
  if vim.regex(vim.fn.glob2regpat(glob)):match_str(path) then
    return true
  end
end

---Build mapping of instruction files from config.
local function build_mapping()
  if not M.config.enabled then return end
  -- Reset always included files
  apply_map = { ['**'] = {} }
    for _, path in ipairs(expand_globs(M.config.simple)) do
      table.insert(apply_map['**'], path)
    end
    -- Add conditional files to their respective globs
    for _, path in ipairs(expand_globs(M.config.conditional)) do
      local fm = frontmatter.parse_frontmatter(path)
      if fm and fm.applyTo then
        for _, g in ipairs(split_globs(fm.applyTo)) do
          apply_map[g] = apply_map[g] or {}
          table.insert(apply_map[g], path)
        end
      end
    end
end

---Add a file to the chat context using the /file slash command.
---@param chat table The chat object to add the file to
---@param file string The file path to add to the context
local function add_instructions(chat, file)
  chat.context:add({
    id = '<file>' .. file .. '</file>',
    path = file,
    source = "codecompanion.strategies.chat.slash_commands.file",
  })
end

---Add relevant instruction files to the context for a given buffer.
---@param bufnr integer Buffer number
function M.sync_context(bufnr)
  if not M.config.enabled then return end
  -- Get current chat
  local chat = require('codecompanion.strategies.chat').buf_get_chat(bufnr)
  if not chat then return end
  -- Get project root
  local project_root = utils.find_project_root(M.config.root_markers)
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
    if add then add_instructions(chat, file) end
  end
end

---Setup the CustomInstructions extension.
---@param opts table|nil Optional configuration overrides
function M.setup(opts)
  if opts then M.config = vim.tbl_deep_extend('force', M.config, opts) end

  -- Build mapping between files/globs and instruction files
  build_mapping()

  -- User commands
  vim.api.nvim_create_user_command('CustomInstructionsReload', build_mapping, {desc='Refresh custom instruction file mapping'})
  vim.api.nvim_create_user_command('CustomInstructionsContextSync', function(opts)
    M.sync_context(opts.args ~= '' and tonumber(opts.args) or vim.api.nvim_get_current_buf())
  end, {desc='Sync custom instructions to context', nargs='?'})

  -- Keymaps
  local keymaps = require("codecompanion.config").strategies.chat.keymaps
  keymaps.sync_context = {
    modes = {
      n = M.config.keymaps.sync_context,
    },
    description = "Add relevant instruction files to the context.",
    callback = function() M.sync_context(vim.api.nvim_get_current_buf()) end,
  }

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
