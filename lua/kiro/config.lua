local M = {}

M.defaults = {
  -- Path to kiro-cli binary
  terminal_cmd = "kiro-cli",
  -- Auto-start when Neovim opens
  auto_start = false,
  -- Default model (nil = use Kiro's default "auto")
  model = nil,
  -- Default agent (nil = use Kiro's default)
  agent = nil,
  -- Trust all tools (skip permission prompts from kiro side)
  trust_all_tools = false,
  -- Log level: "trace", "debug", "info", "warn", "error"
  log_level = "warn",
  -- Window config for chat panel
  window = {
    position = "right", -- "right", "left", "bottom", "top", "float"
    width = 0.4,        -- fraction of editor width (for side panels)
    height = 0.4,       -- fraction of editor height (for bottom/top)
  },
  -- Whether to show tool call progress in chat
  show_tool_calls = true,
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M