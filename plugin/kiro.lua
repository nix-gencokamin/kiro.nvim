-- Plugin entry point: register Neovim user commands
if vim.g.loaded_kiro then return end
vim.g.loaded_kiro = true

local function kiro() return require("kiro") end

-- Core commands
vim.api.nvim_create_user_command("Kiro", function()
  kiro().toggle()
end, { desc = "Toggle Kiro chat panel" })

vim.api.nvim_create_user_command("KiroOpen", function()
  kiro().open()
end, { desc = "Open Kiro chat panel" })

vim.api.nvim_create_user_command("KiroClose", function()
  kiro().close()
end, { desc = "Close Kiro chat panel" })

vim.api.nvim_create_user_command("KiroChat", function()
  kiro().chat()
end, { desc = "Send a message to Kiro" })

vim.api.nvim_create_user_command("KiroSend", function(opts)
  if opts.range > 0 then
    kiro().send_selection()
  elseif opts.args ~= "" then
    kiro().send(opts.args)
  else
    kiro().chat()
  end
end, {
  range = true,
  nargs = "?",
  desc = "Send text or selection to Kiro",
})

vim.api.nvim_create_user_command("KiroAdd", function(opts)
  local file = opts.args ~= "" and opts.args or nil
  kiro().add_file(file)
end, {
  nargs = "?",
  complete = "file",
  desc = "Add file to Kiro context",
})

vim.api.nvim_create_user_command("KiroStart", function()
  kiro().start()
end, { desc = "Start Kiro CLI connection" })

vim.api.nvim_create_user_command("KiroStop", function()
  kiro().stop()
end, { desc = "Stop Kiro CLI connection" })

vim.api.nvim_create_user_command("KiroClear", function()
  kiro().clear()
end, { desc = "Clear Kiro chat and start new session" })

vim.api.nvim_create_user_command("KiroDiffAccept", function()
  kiro().diff_accept()
end, { desc = "Accept Kiro's proposed file change" })

vim.api.nvim_create_user_command("KiroDiffReject", function()
  kiro().diff_reject()
end, { desc = "Reject Kiro's proposed file change" })

-- Auto-setup if user used vim.g.kiro_auto_setup
if vim.g.kiro_auto_setup then
  kiro().setup(type(vim.g.kiro_auto_setup) == "table" and vim.g.kiro_auto_setup or {})
end