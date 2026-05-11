local M = {}


--- Creates a floating window with the given configuration
--- @param config table: The configuration for the floating window
--- @param enter boolean: Whether to enter the window after creation
function M.create_floating_window(config, enter)
  if enter == nil then
    enter = false
  end

  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
  local win = vim.api.nvim_open_win(buf, enter, config)

  return { buf = buf, win = win }
end

return M
