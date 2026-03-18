local M = {}

local levels = { trace = 0, debug = 1, info = 2, warn = 3, error = 4 }
local current_level = 3 -- warn

function M.set_level(level)
  current_level = levels[level] or 3
end

local function log(level, ...)
  if levels[level] < current_level then return end
  local msg = table.concat(vim.tbl_map(tostring, { ... }), " ")
  vim.schedule(function()
    vim.notify("[kiro] " .. msg, vim.log.levels[level:upper()] or vim.log.levels.INFO)
  end)
end

function M.trace(...) log("trace", ...) end
function M.debug(...) log("debug", ...) end
function M.info(...)  log("info",  ...) end
function M.warn(...)  log("warn",  ...) end
function M.error(...) log("error", ...) end

return M