# Project Description: codecompanion-filewise.nvim

`codecompanion-filewise.nvim` is a Neovim plugin designed to provide file-aware AI assistance through a modular extension system. The plugin enables advanced customization of instructions, modes, and prompts on a per-file or per-context basis.

## Extensions

- **custom-instructions**: Manage and inject custom instruction files into the AI context based on file patterns or project configuration.
- **custom-modes**: Define and switch between custom operational modes for the AI assistant, allowing tailored behaviors for different workflows or file types.
- **custom-prompts**: Create and manage reusable prompt templates to streamline and standardize interactions with the AI assistant.

Each extension is independently configurable and can be enabled or disabled as needed.

## Key Features (custom-instructions)

- **Automatic Context Injection:**
  - When a file or buffer is added to the CodeCompanion chat context, the extension automatically adds relevant instruction files if they are not already present.

- **Instruction File Types:**
  - **Simple Custom Instruction Files:** Always included in the context when the context changes (e.g., `.github/copilot-instructions.md`).
  - **Conditional Custom Instruction Files:** Included only if their YAML frontmatter contains an `applyTo` field matching the path of a file/buffer in the context. The `applyTo` field is a comma-separated list of Unix globs. `applyTo: "**"` acts as a catch-all.

- **Configuration:**
  - Users configure two lists: `simple` (always included) and `conditional` (globs for conditional custom instructions), both relative to the project root.
  - The extension can be enabled or disabled via the `enabled` config field.

- **Frontmatter Parsing:**
  - The extension parses YAML frontmatter from markdown files using a Lua YAML parser (`lyaml` or `yaml.nvim`).

- **Slash Command Patching:**
  - The `/buffer` slash command is patched so that after a buffer is added, the extension injects the appropriate instruction files.

- **User Commands:**
  - `CustomInstructionsShow`: Show the current mapping between globs and custom instruction files in a floating window.
  - `CustomInstructionsRefresh`: Re-scan and refresh the mapping.

## Technical Notes

- The extension caches the mapping between globs and custom instruction files in memory for performance.
- If no YAML parser is available, the extension notifies the user and skips conditional custom instructions.
- The extension is designed to be robust and extensible, following CodeCompanion's extension guidelines.

## Goals

- Fine-grained control over AI context and behavior.
- Easy extensibility for new features and workflows.
- Seamless integration with Neovim and project-specific configurations.

