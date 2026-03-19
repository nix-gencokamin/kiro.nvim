-- kiro.nvim - Neovim integration for Kiro CLI
-- Opens kiro-cli chat in a snacks.nvim terminal, like claudecode.nvim does for claude.
local config   = require("kiro.config")
local log      = require("kiro.log")
local terminal = require("kiro.terminal")

local M = {}

function M.toggle()
  terminal.toggle()
end

function M.focus_toggle(override_opts)
  terminal.focus_toggle(override_opts)
end

function M.focus()
  terminal.focus()
end

function M.open()
  terminal.open()
end

function M.close()
  terminal.close()
end

function M.setup(opts)
  config.setup(opts)
  log.set_level(config.options.log_level)
end

return M
