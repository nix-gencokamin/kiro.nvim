-- Chat buffer/window management
local log = require("kiro.log")

local M = {}

local bufnr = nil
local win_id = nil
local ns_id = vim.api.nvim_create_namespace("kiro_chat")

-- Accumulate streaming text for current response
local current_response_lines = {}
local current_response_start = nil  -- line index where current response started
local in_response = false

local function ensure_buf()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then return end
  bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "kiro://chat")
  vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
end

local function buf_append(lines)
  ensure_buf()
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

local function buf_set_last_line(text)
  ensure_buf()
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { text })
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

local function scroll_to_bottom()
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(win_id, { line_count, 0 })
  end
end

function M.get_bufnr()
  ensure_buf()
  return bufnr
end

function M.is_open()
  return win_id ~= nil and vim.api.nvim_win_is_valid(win_id)
end

function M.open(config)
  ensure_buf()
  if M.is_open() then
    vim.api.nvim_set_current_win(win_id)
    return
  end

  config = config or {}
  local position = config.position or "right"
  local width_frac = config.width or 0.4
  local height_frac = config.height or 0.4

  if position == "float" then
    local editor_w = vim.o.columns
    local editor_h = vim.o.lines
    local w = math.floor(editor_w * 0.6)
    local h = math.floor(editor_h * 0.7)
    local col = math.floor((editor_w - w) / 2)
    local row = math.floor((editor_h - h) / 2)
    win_id = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor", width = w, height = h,
      col = col, row = row, style = "minimal", border = "rounded",
      title = " Kiro ", title_pos = "center",
    })
  elseif position == "right" then
    local w = math.floor(vim.o.columns * width_frac)
    vim.cmd("botright " .. w .. "vsplit")
    win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win_id, bufnr)
  elseif position == "left" then
    local w = math.floor(vim.o.columns * width_frac)
    vim.cmd("topleft " .. w .. "vsplit")
    win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win_id, bufnr)
  elseif position == "bottom" then
    local h = math.floor(vim.o.lines * height_frac)
    vim.cmd("botright " .. h .. "split")
    win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win_id, bufnr)
  else
    vim.cmd("split")
    win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win_id, bufnr)
  end

  -- Window options
  vim.api.nvim_win_set_option(win_id, "wrap", true)
  vim.api.nvim_win_set_option(win_id, "linebreak", true)
  vim.api.nvim_win_set_option(win_id, "number", false)
  vim.api.nvim_win_set_option(win_id, "relativenumber", false)
  vim.api.nvim_win_set_option(win_id, "signcolumn", "no")
  vim.api.nvim_win_set_option(win_id, "winbar", " Kiro Chat ")

  -- Close autocmd
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win_id),
    once = true,
    callback = function() win_id = nil end,
  })

  scroll_to_bottom()
end

function M.close()
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_close(win_id, false)
    win_id = nil
  end
end

function M.toggle(config)
  if M.is_open() then
    M.close()
  else
    M.open(config)
  end
end

function M.focus()
  if M.is_open() then
    vim.api.nvim_set_current_win(win_id)
  end
end

-- Add a user message to the chat
function M.add_user_message(text)
  ensure_buf()
  local lines = { "", "## You", "" }
  for _, line in ipairs(vim.split(text, "\n")) do
    table.insert(lines, line)
  end
  table.insert(lines, "")
  buf_append(lines)
  scroll_to_bottom()
end

-- Begin a new Kiro response
function M.begin_response()
  ensure_buf()
  in_response = true
  current_response_lines = {}
  current_response_start = vim.api.nvim_buf_line_count(bufnr)
  buf_append({ "", "## Kiro", "", "" })  -- blank line will be updated as text streams in
  scroll_to_bottom()
end

-- Append a text chunk to the current response (streaming)
function M.append_chunk(text)
  if not in_response then M.begin_response() end
  ensure_buf()

  -- Split incoming text by newlines
  local new_parts = vim.split(text, "\n", { plain = true })
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

  if #new_parts == 1 then
    -- Append to last line
    local last = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1] or ""
    vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { last .. text })
  else
    -- Append first part to last line, then add new lines
    local last = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1] or ""
    local new_lines = {}
    new_lines[1] = last .. new_parts[1]
    for i = 2, #new_parts do
      table.insert(new_lines, new_parts[i])
    end
    vim.api.nvim_buf_set_lines(bufnr, line_count - 1, -1, false, new_lines)
  end

  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  scroll_to_bottom()
end

-- End the current response
function M.end_response(stop_reason)
  if not in_response then return end
  in_response = false
  current_response_lines = {}
  buf_append({ "", "---", "" })
  scroll_to_bottom()
end

-- Add a tool call notification
function M.add_tool_call(title, kind, status)
  ensure_buf()
  local icon = status == "completed" and "✓" or status == "failed" and "✗" or "⟳"
  local line = string.format("> %s [%s] %s", icon, kind or "tool", title or "")
  buf_append({ line })
  scroll_to_bottom()
end

-- Show a status/error message
function M.add_info(text)
  ensure_buf()
  buf_append({ "", "> " .. text, "" })
  scroll_to_bottom()
end

-- Clear the chat buffer
function M.clear()
  ensure_buf()
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  in_response = false
  current_response_lines = {}
end

return M