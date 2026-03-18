# kiro.nvim Development Notes

## Protocol

This plugin communicates with `kiro-cli` via **ACP (Agent Client Protocol)** - JSON-RPC 2.0 over newline-delimited stdio.

### Message Flow
1. Spawn: `kiro-cli acp`
2. Send: `initialize` with `protocolVersion: "2025-06-18"`, `clientInfo`, `workspaceFolders`
3. Send: `session/new` with `cwd`, `workspaceFolders`, `mcpServers: []`
4. Send: `session/prompt` with `sessionId`, `prompt: [{type, text}]`
5. Receive: `session/update` notifications with streaming chunks
6. Receive: `fs/read_text_file`, `fs/write_text_file`, `request_permission` server→client requests

### Key Notifications from Kiro
- `session/update` with `sessionUpdate: "agent_message_chunk"` - streaming text
- `_kiro.dev/metadata` - context usage percentage
- `_kiro.dev/commands/available` - available slash commands

### IDE Tool Requests (Kiro → Neovim)
- `fs/read_text_file` → return `{content: "..."}`
- `fs/write_text_file` → show diff, respond `{accepted: true/false}`
- `request_permission` → respond `{outcome: "allow_once"|"allow_always"|"reject_once"|"reject_always"}`
- `terminal/create` → respond `{terminalId: "..."}`

## Plugin Structure

```
lua/kiro/
  init.lua          Main module (setup, send, toggle, etc.)
  config.lua        Default configuration
  log.lua           Logging utility
  tools.lua         IDE tool request handler
  acp/
    transport.lua   stdio JSON-RPC transport (subprocess management)
    client.lua      ACP protocol client (init, session, prompt)
  ui/
    chat.lua        Chat buffer/window
    diff.lua        Diff view for write_text_file
    input.lua       vim.ui.input wrapper
plugin/kiro.lua     Neovim command registration
```

## Testing

Manually test the ACP connection:
```sh
python3 - <<'EOF'
import subprocess, json, time, threading
proc = subprocess.Popen(['kiro-cli', 'acp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
# ... see scripts/ for full test
EOF
```

## Commands

| Command | Description |
|---------|-------------|
| `:Kiro` | Toggle chat panel |
| `:KiroChat` | Send a message |
| `:KiroSend` | Send selection with message |
| `:KiroAdd [file]` | Add file to context |
| `:KiroStart` | Start Kiro connection |
| `:KiroStop` | Stop Kiro connection |
| `:KiroClear` | Clear chat, new session |
| `:KiroDiffAccept` | Accept proposed file change |
| `:KiroDiffReject` | Reject proposed file change |
