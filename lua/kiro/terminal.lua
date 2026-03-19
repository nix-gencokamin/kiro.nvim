-- Terminal management for kiro-cli chat, modeled after claudecode.nvim's snacks provider
local config = require("kiro.config")
local log = require("kiro.log")

local M = {}

local terminal = nil      -- Snacks terminal instance (or nil)
local terminal_mode = nil -- "sidebar" or "float" — tracks how the current terminal was opened
local has_had_session = false -- true after first terminal is created; used to --resume on mode switch

local function get_cmd(extra_args)
  local cmd = config.options.terminal_cmd or "kiro-cli"
  local resolved = vim.fn.exepath(cmd)
  if resolved ~= "" then cmd = resolved end
  local full = cmd .. " chat"
  if extra_args then full = full .. " " .. extra_args end
  return full
end

local function setup_terminal_events(term_instance)
  -- When the process exits (Ctrl-C, normal exit, crash), clean up so next
  -- toggle creates a fresh terminal instead of reusing the dead buffer.
  term_instance:on("TermClose", function()
    terminal = nil
    vim.schedule(function()
      pcall(function() term_instance:close({ buf = true }) end)
      vim.cmd.checktime()
    end)
  end, { buf = true })

  -- Set keymaps directly on the buffer
  local buf = term_instance.buf
  if not buf then return end
  local opts = { noremap = true, silent = true }

  -- <Esc><Esc> hides the panel (works from terminal mode: first esc exits to normal, second hides)
  vim.keymap.set("t", "<Esc><Esc>", function()
    if terminal then terminal:hide() end
  end, vim.tbl_extend("force", opts, { buffer = buf, desc = "Hide Kiro" }))

  -- q in normal mode hides
  vim.keymap.set("n", "q", function()
    if terminal then terminal:hide() end
  end, vim.tbl_extend("force", opts, { buffer = buf, desc = "Hide Kiro" }))

  -- <Esc> in normal mode hides (so esc-esc also works via: first esc→normal, second esc→hide)
  vim.keymap.set("n", "<Esc>", function()
    if terminal then terminal:hide() end
  end, vim.tbl_extend("force", opts, { buffer = buf, desc = "Hide Kiro" }))

  -- <C-x> unfocuses
  vim.keymap.set("t", "<C-x>", function()
    vim.cmd("wincmd p")
  end, vim.tbl_extend("force", opts, { buffer = buf, desc = "Unfocus Kiro" }))
end

local function build_snacks_opts(override_opts)
  local win_opts = vim.tbl_deep_extend(
    "force",
    config.options.terminal.snacks_win_opts or {},
    override_opts or {},
    {}
  )

  return {
    cwd = vim.fn.getcwd(),
    start_insert = true,
    auto_insert = true,
    auto_close = false,
    win = win_opts,
  }
end

-- ── Snacks provider ───────────────────────────────────────────────────────────

local function snacks_create(override_opts, extra_args)
  local has_snacks, Snacks = pcall(require, "snacks")
  if not has_snacks then
    log.error("snacks.nvim not found; install it or set terminal.provider = 'native'")
    return nil
  end

  local opts = build_snacks_opts(override_opts)
  local term_instance = Snacks.terminal.open(get_cmd(extra_args), opts)

  if term_instance and term_instance:buf_valid() then
    setup_terminal_events(term_instance)
    terminal = term_instance
    has_had_session = true
    return terminal
  end

  return nil
end

local function resolve_mode(override_opts)
  if override_opts and override_opts.position == "float" then return "float" end
  return "sidebar"
end

local function kill_terminal()
  if terminal then
    pcall(function() terminal:close({ buf = true }) end)
    terminal = nil
    terminal_mode = nil
  end
end

local function snacks_toggle(override_opts, extra_args)
  local requested_mode = resolve_mode(override_opts)

  if terminal and terminal:buf_valid() then
    if terminal_mode == requested_mode and not extra_args then
      -- Same mode, no special args: just toggle visibility
      terminal:toggle()
      return
    end
    -- Different mode or special args: destroy the old one and resume in new mode
    local should_resume = has_had_session and not extra_args
    kill_terminal()
    if should_resume then extra_args = "--resume" end
  else
    terminal = nil
    terminal_mode = nil
  end

  terminal_mode = requested_mode
  snacks_create(override_opts, extra_args)
end

local function snacks_focus()
  if terminal and terminal:buf_valid() then
    if terminal:win_valid() then
      terminal:focus()
    else
      terminal:toggle() -- show it
    end
  else
    terminal = nil
    snacks_create()
  end
end

-- ── Native terminal provider ──────────────────────────────────────────────────

local native_bufnr = nil
local native_win = nil

local function native_toggle()
  if native_win and vim.api.nvim_win_is_valid(native_win) then
    vim.api.nvim_win_close(native_win, false)
    native_win = nil
    return
  end

  local w = math.floor(vim.o.columns * 0.30)
  vim.cmd("botright " .. w .. "vsplit")
  native_win = vim.api.nvim_get_current_win()

  if native_bufnr and vim.api.nvim_buf_is_valid(native_bufnr) then
    vim.api.nvim_win_set_buf(native_win, native_bufnr)
  else
    vim.fn.termopen(get_cmd(), {
      on_exit = function()
        vim.schedule(function()
          native_bufnr = nil
          if native_win and vim.api.nvim_win_is_valid(native_win) then
            vim.api.nvim_win_close(native_win, true)
            native_win = nil
          end
        end)
      end,
    })
    native_bufnr = vim.api.nvim_get_current_buf()
  end
  vim.cmd("startinsert")
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.toggle(override_opts, extra_args)
  if config.options.terminal.provider == "snacks" then
    snacks_toggle(override_opts, extra_args)
  else
    native_toggle()
  end
end

function M.resume()
  M.toggle(nil, "--resume")
end

function M.resume_picker()
  M.toggle(nil, "--resume-picker")
end

function M.focus_toggle(override_opts)
  if config.options.terminal.provider == "snacks" then
    -- If terminal is focused, hide it; otherwise focus/create it
    if terminal and terminal:win_valid() then
      local cur_win = vim.api.nvim_get_current_win()
      if terminal.win and terminal.win.win == cur_win then
        terminal:hide()
        return
      end
    end
    snacks_toggle(override_opts)
  else
    native_toggle()
  end
end

function M.focus()
  if config.options.terminal.provider == "snacks" then
    snacks_focus()
  elseif native_win and vim.api.nvim_win_is_valid(native_win) then
    vim.api.nvim_set_current_win(native_win)
    vim.cmd("startinsert")
  else
    native_toggle()
  end
end

function M.open()
  if config.options.terminal.provider == "snacks" then
    if terminal and terminal:buf_valid() and terminal:win_valid() then
      return -- already visible
    end
    snacks_toggle()
  else
    if not (native_win and vim.api.nvim_win_is_valid(native_win)) then
      native_toggle()
    end
  end
end

function M.close()
  if config.options.terminal.provider == "snacks" then
    if terminal and terminal:win_valid() then
      terminal:hide()
    end
  elseif native_win and vim.api.nvim_win_is_valid(native_win) then
    vim.api.nvim_win_close(native_win, false)
    native_win = nil
  end
end

return M
