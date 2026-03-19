-- ACP client: handles protocol handshake, session management, and routing
local transport = require("kiro.acp.transport")
local log = require("kiro.log")

local M = {}

-- State
local session_id = nil
local initialized = false
local on_update_cb = nil   -- called with (update_type, data) for chat updates
local on_request_cb = nil  -- called with (method, params, respond_fn) for IDE tool requests
local workspace_folders = {}

-- Handle incoming notifications/server-requests
local function handle_notification(msg)
  local method = msg.method or ""
  local params = msg.params or {}

  if method == "session/update" then
    -- Streaming AI response chunks and tool call updates
    if on_update_cb then
      on_update_cb(params)
    end

  elseif method == "_kiro.dev/metadata" then
    -- Context usage updates, session ID confirmation
    log.trace("metadata:", vim.fn.json_encode(params))

  elseif method == "_kiro.dev/commands/available" then
    -- Available slash commands
    log.trace("commands available:", #(params.commands or {}), "commands")

  elseif msg.id ~= nil then
    -- Server is making a request to the IDE (needs a response)
    local respond = function(result)
      transport.respond(msg.id, result)
    end
    local respond_err = function(code, errmsg)
      transport.respond_error(msg.id, code, errmsg)
    end

    if on_request_cb then
      on_request_cb(method, params, respond, respond_err, msg.id)
    else
      -- Default: method not found
      transport.respond_error(msg.id, -32601, "Method not found: " .. method)
    end
  else
    log.debug("unhandled notification:", method)
  end
end

-- Initialize the ACP connection
local function do_initialize(cwd, cb)
  local folders = {}
  for _, f in ipairs(workspace_folders) do
    table.insert(folders, { uri = "file://" .. f })
  end
  if #folders == 0 then
    table.insert(folders, { uri = "file://" .. cwd })
  end

  transport.request("initialize", {
    protocolVersion = "2025-06-18",
    clientInfo = { name = "Neovim", version = tostring(vim.version()) },
    workspaceFolders = folders,
  }, function(err, result)
    if err then
      log.error("ACP initialize failed:", err.message or vim.inspect(err))
      if cb then cb(false) end
      return
    end
    log.debug("ACP initialized, agent:", (result.agentInfo or {}).name, "v" .. ((result.agentInfo or {}).version or "?"))
    initialized = true
    if cb then cb(true) end
  end)
end

-- Create a new session
local function do_new_session(cwd, opts, cb)
  local folders = {}
  for _, f in ipairs(workspace_folders) do
    table.insert(folders, { uri = "file://" .. f })
  end
  if #folders == 0 then
    table.insert(folders, { uri = "file://" .. cwd })
  end

  local params = {
    cwd = cwd,
    workspaceFolders = folders,
    mcpServers = {},
  }
  if opts.model then params.model = opts.model end
  if opts.agent then params.agent = opts.agent end

  transport.request("session/new", params, function(err, result)
    if err then
      log.error("ACP session/new failed:", err.message or vim.inspect(err))
      if cb then cb(nil) end
      return
    end
    session_id = result.sessionId
    log.debug("ACP session created:", session_id)
    if cb then cb(session_id) end
  end)
end

-- Public API

-- Start the ACP client (spawn process, handshake, create session)
function M.start(opts, cb)
  opts = opts or {}
  local cmd = opts.terminal_cmd or "kiro-cli"
  local cwd = vim.fn.getcwd()

  -- Set workspace folders from current cwd
  workspace_folders = { cwd }

  transport.set_notification_handler(handle_notification)

  local started = transport.start(cmd, function(code, _signal)
    initialized = false
    session_id = nil
    log.info("kiro-cli exited with code", code)
    if on_update_cb then
      on_update_cb({ sessionUpdate = "_exit", code = code })
    end
  end)

  if not started then
    if cb then cb(false) end
    return
  end

  -- Give the process a moment to start
  vim.defer_fn(function()
    do_initialize(cwd, function(ok)
      if not ok then
        if cb then cb(false) end
        return
      end
      do_new_session(cwd, opts, function(sid)
        if cb then cb(sid ~= nil) end
      end)
    end)
  end, 100)
end

-- Send a prompt to the current session
function M.prompt(content, cb)
  if not session_id then
    log.error("ACP: no active session")
    if cb then cb({ code = -1, message = "no active session" }, nil) end
    return
  end

  -- content can be a string or array of content blocks
  local prompt
  if type(content) == "string" then
    prompt = { { type = "text", text = content } }
  else
    prompt = content
  end

  transport.request("session/prompt", {
    sessionId = session_id,
    prompt = prompt,
  }, function(err, result)
    if cb then cb(err, result) end
  end)
end

-- Cancel the current prompt
function M.cancel()
  if not session_id then return end
  transport.notify("session/cancel", { sessionId = session_id })
end

-- Stop the client, calling cb when the process has actually exited
function M.stop(cb)
  session_id = nil
  initialized = false
  transport.stop(cb)
end

function M.is_running()
  return transport.is_running()
end

function M.get_session_id()
  return session_id
end

-- Set callback for AI response streaming updates
-- callback(params) where params has: sessionUpdate type + content
function M.on_update(cb)
  on_update_cb = cb
end

-- Set callback for IDE tool requests (fs/read_text_file, etc.)
-- callback(method, params, respond_fn, respond_err_fn)
function M.on_request(cb)
  on_request_cb = cb
end

return M