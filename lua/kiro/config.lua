local M = {}

M.defaults = {
  -- Path or command for kiro-cli
  terminal_cmd = "kiro-cli",
  -- Terminal provider: "snacks" or "native"
  terminal = {
    provider = "snacks",
    snacks_win_opts = {
      position = "right",
      width = 0.30,
    },
  },
  -- Log level
  log_level = "warn",
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
