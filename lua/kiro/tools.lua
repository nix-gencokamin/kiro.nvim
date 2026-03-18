-- Handles IDE tool requests from Kiro (fs/*, terminal/*, request_permission)
local log = require("kiro.log")

local M = {}

local diff_module = nil  -- lazy-loaded

local function get_diff()
  if not diff_module then
    diff_module = require("kiro.ui.diff")
  end
  return diff_module
end

-- Handle fs/read_text_file: read file content and return it
local function handle_read_text_file(params, respond, respond_err)
  local path = params.path or params.filePath or params.file_path
  if not path then
    respond_err(-32602, "missing 'path' parameter")
    return
  end

  -- Expand ~ and make absolute
  path = vim.fn.expand(path)

  -- Check if open in a buffer first (get unsaved content)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    respond({ content = table.concat(lines, "\n") })
    return
  end

  -- Fall back to reading from disk
  local ok, content = pcall(function()
    local f = io.open(path, "r")
    if not f then error("cannot open file: " .. path) end
    local c = f:read("*a")
    f:close()
    return c
  end)

  if ok then
    respond({ content = content })
  else
    respond_err(-32000, "Failed to read file: " .. tostring(content))
  end
end

-- Handle fs/write_text_file: show diff and ask for confirmation
local function handle_write_text_file(id, params, respond, respond_err)
  local path = params.path or params.filePath or params.file_path
  if not path then
    respond_err(-32602, "missing 'path' parameter")
    return
  end
  path = vim.fn.expand(path)

  -- Show diff UI
  vim.schedule(function()
    get_diff().show(id, path, params, respond, respond_err)
  end)
end

-- Handle request_permission: show vim.ui.select for user approval
local function handle_request_permission(params, respond, _respond_err)
  local description = params.description or params.message or "Kiro wants to perform an action"

  vim.schedule(function()
    -- Build choices
    local choices = { "Allow once", "Allow always", "Reject once", "Reject always" }
    vim.ui.select(choices, {
      prompt = "Kiro permission request: " .. description,
    }, function(choice)
      if not choice then
        respond({ outcome = "reject_once" })
        return
      end
      local outcome_map = {
        ["Allow once"]   = "allow_once",
        ["Allow always"] = "allow_always",
        ["Reject once"]  = "reject_once",
        ["Reject always"] = "reject_always",
      }
      respond({ outcome = outcome_map[choice] or "reject_once" })
    end)
  end)
end

-- Main request dispatcher
function M.handle(method, params, respond, respond_err, request_id)
  log.debug("tool request:", method)

  if method == "fs/read_text_file" then
    handle_read_text_file(params, respond, respond_err)

  elseif method == "fs/write_text_file" then
    handle_write_text_file(request_id, params, respond, respond_err)

  elseif method == "request_permission" then
    handle_request_permission(params, respond, respond_err)

  elseif method == "terminal/create" then
    -- Basic terminal support: create a Neovim terminal buffer
    local term_id = tostring(math.random(100000, 999999))
    -- For now just acknowledge; full terminal integration is TODO
    respond({ terminalId = term_id })

  elseif method == "terminal/output" then
    respond({ output = "", exitCode = nil })

  elseif method == "terminal/release" or method == "terminal/kill" then
    respond({})

  elseif method == "terminal/wait_for_exit" then
    respond({ exitCode = 0 })

  else
    log.debug("unhandled IDE request:", method)
    respond_err(-32601, "Method not found: " .. method)
  end
end

return M