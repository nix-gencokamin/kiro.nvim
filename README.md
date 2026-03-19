# kiro.nvim

Neovim plugin for [Kiro CLI](https://kiro.dev) — brings Kiro's AI agent into your editor via the Agent Client Protocol (ACP).

## Features

- **Chat panel** — streaming AI responses rendered as Markdown in a side/bottom/float window
- **Context-aware** — send the current file, a visual selection, or any file as context
- **File diffs** — Kiro's proposed file edits open in a vimdiff tab; accept or reject with a keypress
- **Permission prompts** — tool permission requests surface as `vim.ui.select` dialogs
- **Session management** — clear and restart sessions without leaving Neovim

## Requirements

- Neovim 0.9+
- [`kiro-cli`](https://kiro.dev/docs/cli/) installed and authenticated (`kiro-cli login`)

## Installation

### lazy.nvim

```lua
{
  "your-username/kiro.nvim",
  config = function()
    require("kiro").setup()
  end,
}
```

### With options

```lua
{
  "your-username/kiro.nvim",
  config = function()
    require("kiro").setup({
      terminal_cmd  = "kiro-cli",   -- path to kiro-cli binary
      auto_start    = false,        -- start automatically on Neovim load
      model         = nil,          -- nil = Kiro's default ("auto"), or e.g. "claude-sonnet-4.6"
      agent         = nil,          -- nil = default agent, or e.g. "kiro_planner"
      show_tool_calls = true,       -- show tool call progress in chat
      window = {
        position = "right",         -- "right" | "left" | "bottom" | "top" | "float"
        width    = 0.4,             -- fraction of editor width (side panels)
        height   = 0.4,             -- fraction of editor height (bottom/top panels)
      },
    })
  end,
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:Kiro` | Toggle the chat panel |
| `:KiroChat` | Type and send a message |
| `:KiroSend [text]` | Send text (or visual selection) to Kiro |
| `:KiroAdd [file]` | Add a file to the next prompt's context |
| `:KiroStart` | Start the Kiro CLI connection |
| `:KiroStop` | Stop the Kiro CLI connection |
| `:KiroClear` | Clear chat history and start a new session |
| `:KiroDiffAccept` | Accept Kiro's proposed file change |
| `:KiroDiffReject` | Reject Kiro's proposed file change |

## Workflow

**Chat:**
```
:Kiro          → opens the chat panel
:KiroChat      → prompts for a message, streams response into the panel
```

**Send selection:**
```
V{select}      → visually select code
:KiroSend      → prompts for a message; selection is included as context
```

**Add file context:**
```
:KiroAdd path/to/file.rb    → adds file content to the next message
:KiroChat                   → sends message with the file attached
```

**File edits:**

When Kiro wants to edit a file, a vimdiff tab opens showing the current vs proposed content:

| Key | Action |
|-----|--------|
| `<leader>da` | Accept the change |
| `<leader>dd` | Reject the change |

Or use `:KiroDiffAccept` / `:KiroDiffReject` from any buffer.

## Protocol

kiro.nvim communicates with `kiro-cli` using the [Agent Client Protocol (ACP)](https://agentclientprotocol.com) — JSON-RPC 2.0 over newline-delimited stdio. See [CLAUDE.md](CLAUDE.md) for implementation details.

## License

MIT