<div align="center">
  <h1 align="center">· CodeCompanion Filewise ·</h1>

  <p align="center">
    File-aware AI assistance for Neovim via modular CodeCompanion extensions
    <br/>
    <br/>
    <a href="https://github.com/olimorris/codecompanion.nvim/releases/tag/v17.18.0">
        <img src="https://img.shields.io/badge/CodeCompanion-v17.18.0-C678DD?style=for-the-badge">
    </a>
    <a href="https://neovim.io">
        <img src="https://img.shields.io/badge/Neovim-57A143?style=for-the-badge&logo=neovim&logoColor=white">
    </a>
    <a href="https://www.lua.org">
        <img src="https://img.shields.io/badge/Lua-2C2D72?style=for-the-badge&logo=lua&logoColor=white">
    </a>
    <a href="https://opensource.org/licenses/MIT">
        <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge">
    </a>
  </p>
</div>

## Overview

`codecompanion-filewise.nvim` is a [CodeCompanion](https://github.com/olimorris/codecompanion.nvim) extensions plugin that brings file-aware AI assistance to your workflow. It enables advanced customization of instructions, modes, and prompts on a per-file or per-context basis, making your AI interactions smarter and more relevant to your project.

> [!NOTE]
> This plugin aims at providing full compatibility with instruction, prompt, and chatmode Markdown files [used by VS Code](https://code.visualstudio.com/docs/copilot/customization/overview), making it easy to share and reuse your AI workflows across editors.

## Features

- **Custom Instructions**: Inject custom instruction files into the AI context automatically, with support for always-included and conditional instructions based on YAML frontmatter.
- **Custom Modes**: Define and switch between operational modes for tailored AI behavior.
- **Custom Prompts**: Create and manage reusable prompt templates to streamline and standardize interactions with the AI assistant.

## Getting Started

### Installation

> [!IMPORTANT]
> This plugin requires the Lua [lyaml](https://luarocks.org/modules/gvvaughan/lyaml) library for YAML parsing.

Use your favorite Neovim plugin manager.

<details>
<summary>lazy.nvim</summary>

Install as a dependency of `olimorris/codecompanion.nvim`.

```lua
{
    "olimorris/codecompanion.nvim",
    dependencies = {
        "dyamon/codecompanion-filewise.nvim"
        -- other plugins...
    }
}
```

</details>

### Basic Usage

Custom instruction files, prompts and chat modes are provided as three separate extensions for CodeCompanion;
as such you will need to enable them separately.

## Configuration

Configuration for each extension is done via the `codecompanion.setup` call, under the `extensions` table. Below are the default values and descriptions for each extension:

### Custom Instructions

```lua
require'codecompanion'.setup {
  extensions = {
    custom_instructions = {
      enabled = true,
      opts = {
        simple = {
          '.github/copilot-instructions.md',
          (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')) .. '/codecompanion/filewise/instructions/copilot-instructions.md',
          '.ai/rules.md', '.ai/*.rules.md',
          '.rules',
          '.goosehints',
          '.cursorrules',
          '.windsurfrules',
          '.clinerules',
          'AGENT.md', 'AGENTS.md', 'CLAUDE.md',
          '.codecompanionrules',
        },
        conditional = {
          '.github/instructions/*.instructions.md',
          (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')) .. '/codecompanion/filewise/instructions/*.instructions.md',
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
    }
  }
}
```

**Config options:**
- `simple`: list of instruction files/globs that will always be included on a trigger.
- `conditional`: list of instruction files/globs included conditionally (based on the `applyTo` field in the [YAML frontmatter](https://code.visualstudio.com/docs/copilot/customization/custom-instructions#_instructions-file-format)).
- `triggers`: events and commands that trigger context sync.
- `keymaps`: custom keymaps.
- `root_markers`: files/dirs used to detect the project root.

#### Triggers

Context synchronization is automatically triggered on certain events (e.g., user events raised by the CodeCompanion plugin).
Additionally, the extension will patch some of the variables and slash commands provided by CodeCompanion.

As an example, when `/file` is patched, using the command to add `path/to/file.lua` will trigger the addition of any "simple" instruction file, alongside any "conditional" instruction file for which its condition is matched.

> [!NOTE]
> At the time of writing, context injection is a bit limited in CodeCompanion.
> As such, when using the patched variable `#buffer` any relevant instruction file will appear in the context *after* the agent is done replying.

#### Commands

- `:CustomInstructionsReload` — Refresh custom instruction file mapping.
- `:CustomInstructionsContextSync` — Sync custom instructions to context (assigned by default to `gi`.

### Custom Modes

```lua
require'codecompanion'.setup {
  extensions = {
    custom_modes = {
      enabled = true,
      opts = {
        mode_dirs = {
          ".github/chatmodes",
          (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')) .. '/codecompanion/filewise/chatmodes',
        },
        model_map = {},
        tool_map = {},
        format_content = nil,
        root_markers = { '.git', '.github' },
      }
    }
  }
}
```

**Config options:**
- `mode_dirs`: directories to scan for chatmode files.
- `model_map`: map Copilot AI model names to CodeCompanion.
- `tool_map`: map Copilot tool names to CodeCompanion.
- `format_content`: function to format prompt content; it takes the body of the prompt as input and expects it as output (possibly with some user-defined modifications. This is useful to perform additional content injection into the prompt body.
- `root_markers`: files/dirs to detect the project root.

#### Further customize the prompt body

You can use the `format_content` function to preprocess the body of your chatmode prompt before it is injected into the editor. For example, to substitute any occurrence of `${today}` with the current date:

```lua
format_content = function(body)
  return body:gsub("%${today}", os.date("%d/%m/%Y"))
end
```

This allows you to dynamically inject values or perform custom formatting on your prompts.

> [!NOTE]
> The extension handles most [VS Code variables](https://code.visualstudio.com/docs/copilot/customization/prompt-files#_prompt-file-format) already, even input variables.

#### Model and tool maps

[Chat modes](https://code.visualstudio.com/docs/copilot/customization/custom-instructions#_instructions-file-format) support some level of metadata in the YAML frontmatter of the Markdown file.
When specifying AI models and tools, there might not be a 1:1 correspondence between what is considered a valid keyword in VS Code and CodeCompanion.
Use these maps to optionally translate these keywords.

```lua
{
  model_map = {
    ['GPT 4.1'] = 'gpt-4.1',
    ['Clause Sonnet 3.7'] = 'claude-3.7-sonnet',
  },
  tool_map = {
    fetch = '@{fetch_webpage}',
    changes = '@{get_changed_files}',
    problems = '#{lsp}',
    codebase = { '@{file_search}', '@{grep_search}', '@{list_code_usages}', '@{vectorcode_toolbox}' },
  },
}
```

### Custom Prompts

```lua
require'codecompanion'.setup {
  extensions = {
    custom_prompts = {
      enabled = true,
      opts = {
        prompt_dirs = {
          ".github/prompts",
          (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')) .. '/codecompanion/filewise/prompts',
        },
        prompt_role = "user",
        model_map = {},
        tool_map = {},
        format_content = function(body) return body:gsub('^#','###') end,
        root_markers = { '.git', '.github' },
      }
    }
  }
}
```
**Config options:**
- `prompt_dirs`: directories to scan for prompt files.
- `prompt_role`: role used for the prompt entry (see the `role` option in the [CodeCompanion docs](https://codecompanion.olimorris.dev/extending/prompts.html)).
- `model_map`: map Copilot model names to CodeCompanion.
- `tool_map`: map Copilot tool names to CodeCompanion.
- `format_content`: function to format the prompt content.
- `root_markers`: Files/dirs to detect the project root.

#### Further customize the prompt body

See the corresponding section in the **Custom modes** extension.

#### Model and tool maps

See the corresponding section in the **Custom modes** extension.

## Acknowledgements

- [Oli Morris](https://github.com/olimorris) for creating [CodeCompanion.nvim](https://codecompanion.olimorris.dev)
- [Alexei Nunez](https://github.com/arnm) and their extension [CodeCompanion Rules](https://github.com/olimorris/codecompanion.nvim/discussions/1718)

## License

MIT
