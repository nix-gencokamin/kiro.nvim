-- Diff UI for fs/write_text_file requests
local log = require("kiro.log")

local M = {}

-- Active diff state: write_id -> {bufnr_orig, bufnr_new, win_orig, win_new, path, respond, respond_err}
local active_diffs = {}

local function apply_write(path, params)
  local op = params.operation or params.op
  if not op then
    -- Fallback: try direct content field
    local content = params.content
    if content then
      local f = io.open(path, "w")
      if f then f:write(content); f:close() end
    end
    return
  end

  -- Handle strReplace operation
  if op.strReplace or params.strReplace then
    local sr = op.strReplace or params.strReplace
    local f = io.open(path, "r")
    if not f then return end
    local content = f:read("*a"); f:close()
    local new_content = content:gsub(vim.pesc(sr.oldStr or sr.old_str or ""), sr.newStr or sr.new_str or "", sr.replaceAll and 0 or 1)
    f = io.open(path, "w")
    if f then f:write(new_content); f:close() end

  -- Handle insert operation
  elseif op.insert or params.insert then
    local ins = op.insert or params.insert
    local f = io.open(path, "r")
    local lines = {}
    if f then
      for line in f:lines() do table.insert(lines, line) end
      f:close()
    end
    local insert_line = ins.insertLine or ins.insert_line
    local new_lines = ins.content and vim.split(ins.content, "\n") or {}
    if insert_line then
      for i, line in ipairs(new_lines) do
        table.insert(lines, insert_line + i - 1, line)
      end
    else
      for _, line in ipairs(new_lines) do
        table.insert(lines, line)
      end
    end
    f = io.open(path, "w")
    if f then f:write(table.concat(lines, "\n")); f:close() end

  -- Handle create operation (full content)
  elseif op.create or params.create then
    local content = (op.create or params.create).content or ""
    local f = io.open(path, "w")
    if f then f:write(content); f:close() end
  end
end

local function compute_new_content(path, params)
  -- Read current content
  local current = ""
  local f = io.open(path, "r")
  if f then current = f:read("*a"); f:close() end

  -- Simulate the operation on a copy
  local tmp = vim.fn.tempname()
  local tf = io.open(tmp, "w")
  if tf then tf:write(current); tf:close() end

  apply_write(tmp, params)

  local nf = io.open(tmp, "r")
  local new_content = ""
  if nf then new_content = nf:read("*a"); nf:close() end
  vim.fn.delete(tmp)
  return current, new_content
end

function M.show(write_id, path, params, respond, respond_err)
  local id_str = tostring(write_id)
  local current, new_content = compute_new_content(path, params)

  -- Create buffers for diff
  local bufnr_orig = vim.api.nvim_create_buf(false, true)
  local bufnr_new  = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_name(bufnr_orig, "kiro://diff/original/" .. id_str)
  vim.api.nvim_buf_set_name(bufnr_new,  "kiro://diff/proposed/" .. id_str)

  vim.api.nvim_buf_set_lines(bufnr_orig, 0, -1, false, vim.split(current, "\n"))
  vim.api.nvim_buf_set_lines(bufnr_new,  0, -1, false, vim.split(new_content, "\n"))

  -- Mark as readonly
  for _, b in ipairs({ bufnr_orig, bufnr_new }) do
    vim.api.nvim_buf_set_option(b, "modifiable", false)
    vim.api.nvim_buf_set_option(b, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(b, "swapfile", false)
  end

  -- Set filetype for syntax highlighting
  local ft = vim.filetype.match({ filename = path }) or ""
  for _, b in ipairs({ bufnr_orig, bufnr_new }) do
    if ft ~= "" then
      vim.api.nvim_buf_set_option(b, "filetype", ft)
    end
  end

  -- Open diff windows (like vimdiff)
  vim.cmd("tabnew")
  local win_orig = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win_orig, bufnr_orig)
  vim.cmd("diffthis")

  vim.cmd("vsplit")
  local win_new = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win_new, bufnr_new)
  vim.cmd("diffthis")

  -- Set window titles
  vim.api.nvim_win_set_option(win_orig, "winbar", "  CURRENT: " .. vim.fn.fnamemodify(path, ":~:."))
  vim.api.nvim_win_set_option(win_new,  "winbar", "  PROPOSED by Kiro  [<leader>da accept] [<leader>dd reject]")

  active_diffs[id_str] = {
    bufnr_orig = bufnr_orig,
    bufnr_new = bufnr_new,
    win_orig = win_orig,
    win_new = win_new,
    path = path,
    params = params,
    new_content = new_content,
    respond = respond,
    respond_err = respond_err,
    tabnr = vim.api.nvim_get_current_tabpage(),
  }

  -- Set up keymaps in the diff buffers
  local opts = { noremap = true, silent = true }
  for _, b in ipairs({ bufnr_orig, bufnr_new }) do
    vim.api.nvim_buf_set_keymap(b, "n", "<leader>da",
      ("<cmd>lua require('kiro.ui.diff').accept(%q)<CR>"):format(id_str), opts)
    vim.api.nvim_buf_set_keymap(b, "n", "<leader>dd",
      ("<cmd>lua require('kiro.ui.diff').reject(%q)<CR>"):format(id_str), opts)
  end

  -- Notify user
  vim.notify(
    string.format("[kiro] File change proposed: %s\n  <leader>da to accept, <leader>dd to reject",
      vim.fn.fnamemodify(path, ":~:.")),
    vim.log.levels.INFO
  )
end

function M.accept(id_str)
  local diff = active_diffs[id_str]
  if not diff then
    log.warn("diff.accept: no active diff for id", id_str)
    return
  end

  -- Write the new content
  local f = io.open(diff.path, "w")
  if f then
    f:write(diff.new_content)
    f:close()
  else
    diff.respond_err(-32000, "Failed to write file: " .. diff.path)
    M._close(id_str)
    return
  end

  -- Reload any open buffer for this file
  local bufnr = vim.fn.bufnr(diff.path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("edit!") end)
  end

  diff.respond({ accepted = true })
  M._close(id_str)
  vim.notify("[kiro] Change accepted: " .. vim.fn.fnamemodify(diff.path, ":~:."), vim.log.levels.INFO)
end

function M.reject(id_str)
  local diff = active_diffs[id_str]
  if not diff then
    log.warn("diff.reject: no active diff for id", id_str)
    return
  end
  diff.respond({ accepted = false })
  M._close(id_str)
  vim.notify("[kiro] Change rejected", vim.log.levels.INFO)
end

function M._close(id_str)
  local diff = active_diffs[id_str]
  if not diff then return end
  active_diffs[id_str] = nil

  -- Close diff tab/windows
  pcall(function()
    if vim.api.nvim_tabpage_is_valid(diff.tabnr) then
      vim.api.nvim_set_current_tabpage(diff.tabnr)
      vim.cmd("tabclose")
    end
  end)
end

function M.get_pending()
  return vim.tbl_keys(active_diffs)
end

return M