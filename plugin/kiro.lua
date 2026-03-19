if vim.g.loaded_kiro then return end
vim.g.loaded_kiro = true

local function kiro() return require("kiro") end
local function term() return require("kiro.terminal") end

vim.api.nvim_create_user_command("Kiro", function()
  kiro().toggle()
end, { desc = "Toggle Kiro chat panel" })

vim.api.nvim_create_user_command("KiroOpen", function()
  kiro().open()
end, { desc = "Open Kiro chat panel" })

vim.api.nvim_create_user_command("KiroClose", function()
  kiro().close()
end, { desc = "Close Kiro chat panel" })

vim.api.nvim_create_user_command("KiroFocus", function()
  kiro().focus()
end, { desc = "Focus Kiro chat panel" })

vim.api.nvim_create_user_command("KiroResume", function()
  term().resume()
end, { desc = "Resume most recent Kiro conversation" })

vim.api.nvim_create_user_command("KiroResumePicker", function()
  term().resume_picker()
end, { desc = "Pick a Kiro conversation to resume" })
