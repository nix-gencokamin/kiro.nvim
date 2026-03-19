-- kiro.nvim - Neovim integration for Kiro CLI via Agent Client Protocol (ACP)
local config = require("kiro.config")
local log    = require("kiro.log")
local client = require("kiro.acp.client")
local tools  = require("kiro.tools")
local chat   = require("kiro.ui.chat")
local input  = require("kiro.ui.input")

local M = {}

-- Pending context to include in the next prompt
local pending_context = {}

-- Whether we're currently waiting for a response
local waiting_for_response = false

-- Handle streaming updates from Kiro
local function on_update(params)
  local update_type = params.sessionUpdate or params.update_type or ""

  if update_type == "_exit" then
    chat.add_info("Kiro CLI process exited (code " .. tostring(params.code) .. ")")
    waiting_for_response = false
    return
  end

  if update_type == "agent_message_chunk" then
    local content = params.content or {}
    if type(content) == "table" and content.text then
      chat.append_chunk(content.text)
    elseif type(content) == "string" then
      chat.append_chunk(content)
    end

  elseif update_type == "agent_thought_chunk" then
    -- Reasoning/thinking chunks (optional display)
    local content = params.content or {}
    if config.options.show_tool_calls then
      local text = type(content) == "table" and content.text or tostring(content)
      if text and text ~= "" then
        chat.append_chunk(text)
      end
    end

  elseif update_type == "tool_call" then
    if config.options.show_tool_calls then
      local tc = params.toolCall or params.tool_call or {}
      chat.add_tool_call(tc.title or "tool call", tc.kind or "tool", tc.status or "running")
    end

  elseif update_type == "tool_call_update" then
    -- Optional: update existing tool call status
    if config.options.show_tool_calls then
      local tc = params.toolCall or params.tool_call or {}
      if (tc.status == "completed" or tc.status == "failed") then
        chat.add_tool_call(tc.title or "tool call", tc.kind or "tool", tc.status)
      end
    end

  elseif update_type == "plan" then
    -- Agent shared a plan
    local plan = params.plan or {}
    if plan.title then
      chat.add_info("Plan: " .. plan.title)
    end
  end
end

-- Handle IDE tool requests from Kiro
local function on_request(method, params, respond, respond_err, request_id)
  tools.handle(method, params, respond, respond_err, request_id)
end

-- Start the Kiro ACP client
function M.start(cb)
  if client.is_running() then
    log.info("Kiro is already running")
    if cb then cb(true) end
    return
  end

  client.on_update(on_update)
  client.on_request(on_request)

  client.start(config.options, function(ok)
    if ok then
      chat.add_info("Connected to Kiro CLI.")
    else
      chat.add_info("ERROR: Failed to start kiro-cli. Check that it is installed and on PATH.")
    end
    if cb then cb(ok) end
  end)
end

-- Stop the Kiro ACP client
function M.stop()
  client.stop()
  waiting_for_response = false
  log.info("Kiro stopped")
end

-- Toggle the chat panel
function M.toggle()
  if chat.is_open() then
    chat.close()
    return
  end
  -- Open window immediately, then connect if needed
  chat.open(config.options.window)
  if not client.is_running() then
    chat.add_info("Connecting to Kiro CLI...")
    M.start()
  end
end

-- Open/focus the chat panel
function M.open()
  chat.open(config.options.window)
  if not client.is_running() then
    chat.add_info("Connecting to Kiro CLI...")
    M.start()
  end
end

-- Close the chat panel
function M.close()
  chat.close()
end

-- Send a message to Kiro
function M.send(text)
  if not text or text == "" then return end

  if not client.is_running() then
    M.start(function(ok)
      if ok then M.send(text) end
    end)
    return
  end

  -- Ensure chat is open
  if not chat.is_open() then
    chat.open(config.options.window)
  end

  -- Build content blocks
  local content_blocks = {}

  -- Add any pending context first
  for _, ctx in ipairs(pending_context) do
    table.insert(content_blocks, ctx)
  end
  pending_context = {}

  -- Add the user's message
  table.insert(content_blocks, { type = "text", text = text })

  -- Show user message in chat
  local display = text
  chat.add_user_message(display)
  chat.begin_response()
  waiting_for_response = true

  client.prompt(content_blocks, function(err, result)
    waiting_for_response = false
    if err then
      chat.end_response()
      chat.add_info("Error: " .. (err.message or vim.inspect(err)))
    else
      local stop = result and result.stopReason or "end_turn"
      chat.end_response(stop)
    end
  end)
end

-- Prompt user for input and send
function M.chat()
  input.prompt({ prompt = "Message Kiro: " }, function(text)
    M.send(text)
  end)
end

-- Send visual selection to Kiro as context
function M.send_selection()
  -- Get visual selection
  local start_pos = vim.fn.getpos("'<")
  local end_pos   = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(
    0,
    start_pos[2] - 1,
    end_pos[2],
    false
  )

  if #lines == 0 then
    log.warn("No selection")
    return
  end

  -- Trim last line to end column
  if #lines > 0 and end_pos[3] < #lines[#lines] then
    lines[#lines] = lines[#lines]:sub(1, end_pos[3])
  end

  local file = vim.fn.expand("%:p")
  local ft = vim.bo.filetype
  local selection_text = table.concat(lines, "\n")

  -- Add as context block
  local context_block = {
    type = "text",
    text = string.format("```%s\n# %s (lines %d-%d)\n%s\n```",
      ft, vim.fn.fnamemodify(file, ":~:."),
      start_pos[2], end_pos[2],
      selection_text)
  }
  table.insert(pending_context, context_block)

  -- Open input for the message
  input.prompt({ prompt = "Message about selection: " }, function(text)
    M.send(text)
  end)
end

-- Add a file to the next prompt's context
function M.add_file(filepath)
  filepath = filepath or vim.fn.expand("%:p")
  if not filepath or filepath == "" then
    log.warn("No file specified")
    return
  end

  filepath = vim.fn.expand(filepath)
  local f = io.open(filepath, "r")
  if not f then
    log.error("Cannot read file:", filepath)
    return
  end
  local content = f:read("*a")
  f:close()

  local ft = vim.filetype.match({ filename = filepath }) or ""
  table.insert(pending_context, {
    type = "text",
    text = string.format("File: %s\n```%s\n%s\n```",
      vim.fn.fnamemodify(filepath, ":~:."), ft, content)
  })

  log.info("Added to context:", vim.fn.fnamemodify(filepath, ":~:."))
end

-- Clear the chat buffer and start a new session
function M.clear()
  chat.clear()
  chat.open(config.options.window)
  chat.add_info("Starting new session...")
  -- Wait for process to actually exit before restarting
  client.stop(function()
    client.on_update(on_update)
    client.on_request(on_request)
    client.start(config.options, function(ok)
      if ok then
        chat.add_info("New session started.")
      end
    end)
  end)
end

-- Accept pending diff
function M.diff_accept()
  local diff = require("kiro.ui.diff")
  local pending = diff.get_pending()
  if #pending == 0 then
    log.warn("No pending diffs")
    return
  end
  diff.accept(pending[1])
end

-- Reject pending diff
function M.diff_reject()
  local diff = require("kiro.ui.diff")
  local pending = diff.get_pending()
  if #pending == 0 then
    log.warn("No pending diffs")
    return
  end
  diff.reject(pending[1])
end

-- Plugin setup
function M.setup(opts)
  config.setup(opts)
  log.set_level(config.options.log_level)

  if config.options.auto_start then
    -- Defer to let Neovim finish initializing
    vim.defer_fn(function()
      M.start()
    end, 500)
  end
end

return M