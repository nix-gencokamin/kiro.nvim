-- Input handling: floating prompt for sending messages to Kiro
local M = {}

-- Show a floating input window and call cb(text) when submitted
-- Returns nil if user cancels
function M.prompt(opts, cb)
  opts = opts or {}
  local prompt_text = opts.prompt or "Message Kiro: "
  local default = opts.default or ""

  -- Use vim.ui.input for simplicity
  vim.ui.input({
    prompt = prompt_text,
    default = default,
    completion = "file",
  }, function(input)
    if input and input ~= "" then
      cb(input)
    end
  end)
end

return M