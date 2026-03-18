-- ACP stdio transport: manages the kiro-cli subprocess and JSON-RPC I/O
local log = require("kiro.log")

local M = {}

-- State
local process = nil   -- uv process handle
local stdin = nil     -- uv pipe for writing to process
local stdout = nil    -- uv pipe for reading from process
local stderr_pipe = nil
local read_buf = ""   -- partial line buffer
local message_handlers = {}  -- id -> callback for pending requests
local notification_handler = nil  -- callback for notifications/server requests
local next_id = 1

local function get_id()
  local id = next_id
  next_id = next_id + 1
  return id
end

-- Send a raw JSON-RPC message
local function send_raw(msg)
  if not stdin then
    log.error("transport: not connected")
    return
  end
  local json = vim.fn.json_encode(msg) .. "\n"
  log.trace("ACP SEND:", json:sub(1, 200))
  stdin:write(json)
end

-- Handle a single parsed JSON-RPC message
local function handle_message(msg)
  log.trace("ACP RECV:", vim.fn.json_encode(msg):sub(1, 300))

  if msg.id ~= nil and (msg.result ~= nil or msg.error ~= nil) then
    -- It's a response to one of our requests
    local cb = message_handlers[msg.id]
    if cb then
      message_handlers[msg.id] = nil
      cb(msg.error, msg.result)
    else
      log.debug("transport: no handler for response id", msg.id)
    end
  elseif msg.method then
    -- It's a notification or server request (server→client)
    if notification_handler then
      notification_handler(msg)
    else
      log.debug("transport: no notification handler for", msg.method)
    end
  end
end

-- Process incoming data (may contain multiple newline-delimited messages)
local function on_data(data)
  if not data then return end
  read_buf = read_buf .. data
  while true do
    local nl = read_buf:find("\n")
    if not nl then break end
    local line = read_buf:sub(1, nl - 1)
    read_buf = read_buf:sub(nl + 1)
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local ok, msg = pcall(vim.fn.json_decode, line)
      if ok and type(msg) == "table" then
        vim.schedule(function() handle_message(msg) end)
      else
        log.debug("transport: failed to parse line:", line:sub(1, 100))
      end
    end
  end
end

-- Send a request and get response via callback
function M.request(method, params, callback)
  local id = get_id()
  message_handlers[id] = callback
  send_raw({ jsonrpc = "2.0", id = id, method = method, params = params })
  return id
end

-- Send a notification (no response expected)
function M.notify(method, params)
  send_raw({ jsonrpc = "2.0", method = method, params = params })
end

-- Send a response to a server request
function M.respond(id, result)
  send_raw({ jsonrpc = "2.0", id = id, result = result })
end

-- Send an error response to a server request
function M.respond_error(id, code, message)
  send_raw({ jsonrpc = "2.0", id = id, error = { code = code, message = message } })
end

-- Set the notification/server-request handler
function M.set_notification_handler(handler)
  notification_handler = handler
end

-- Start the kiro-cli acp subprocess
function M.start(cmd, on_exit_cb)
  if process then
    log.warn("transport: already running")
    return false
  end

  stdin = vim.loop.new_pipe(false)
  stdout = vim.loop.new_pipe(false)
  stderr_pipe = vim.loop.new_pipe(false)

  -- Build args: cmd may be "kiro-cli" or a full path
  local parts = vim.split(cmd, "%s+")
  local bin = parts[1]
  local args = vim.list_slice(parts, 2)
  table.insert(args, "acp")

  local handle, pid = vim.loop.spawn(bin, {
    args = args,
    stdio = { stdin, stdout, stderr_pipe },
    cwd = vim.fn.getcwd(),
  }, function(code, signal)
    process = nil
    stdin = nil
    stdout = nil
    stderr_pipe = nil
    read_buf = ""
    -- Fail all pending requests
    for id, cb in pairs(message_handlers) do
      message_handlers[id] = nil
      vim.schedule(function()
        cb({ code = -1, message = "process exited (code=" .. code .. ")" }, nil)
      end)
    end
    if on_exit_cb then
      vim.schedule(function() on_exit_cb(code, signal) end)
    end
  end)

  if not handle then
    log.error("transport: failed to spawn", bin)
    stdin:close()
    stdout:close()
    stderr_pipe:close()
    stdin, stdout, stderr_pipe = nil, nil, nil
    return false
  end

  process = handle
  log.debug("transport: spawned pid", pid)

  stdout:read_start(function(err, data)
    if err then log.error("transport: stdout read error:", err) return end
    if data then on_data(data) end
  end)

  stderr_pipe:read_start(function(err, data)
    if err then return end
    if data and data:find("[Ee]rror") then
      log.debug("kiro-cli stderr:", data:sub(1, 200))
    end
  end)

  return true
end

-- Stop the subprocess
function M.stop()
  if process then
    process:kill("sigterm")
    -- uv will call the exit callback which cleans up
  end
end

function M.is_running()
  return process ~= nil
end

return M