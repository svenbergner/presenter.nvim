local M = {}

--- Default executor for lua code
--- @param block presenter.Block
M.execute_lua_code = function(block)
  -- Overwrite the default print function to capture all of the output
  -- Store the original print function
  local original_print = print

  local output = {}

  -- Redefine the print function
  print = function(...)
    local args = { ... }
    local message = table.concat(vim.tbl_map(tostring, args), "\t")
    table.insert(output, message)
  end

  -- Call the provided code block
  local chunk = loadstring(block.code)
  pcall(function()
    if not chunk then
      table.insert(output, " <<<BROKEN CODE BLOCK>>>")
    else
      chunk()
    end

    return output
  end)

  -- Restore the original print function
  print = original_print

  return output
end

--- Default executor for Rust code
---@param block presenter.Block
M.execute_rust_code = function(block)
  local tempfile = vim.fn.tempname() .. ".rs"
  local outputfile = tempfile:sub(1, -4)
  vim.fn.writefile(vim.split(block.code, "\n"), tempfile)
  local result = vim.system({ "rustc", tempfile, "-o", outputfile }, { text = true }):wait()
  if result.code ~= 0 then
    local output = vim.split(result.stderr, "\n")
    return output
  end
  result = vim.system({ outputfile }, { text = true }):wait()
  return vim.split(result.stdout, "\n")
end

M.create_system_executor = function(program)
  return function(block)
    local tempfile = vim.fn.tempname()
    vim.fn.writefile(vim.split(block.code, "\n"), tempfile)
    local result = vim.system({ program, tempfile }, { text = true }):wait()
    return vim.split(result.stdout, "\n")
  end
end

M.defaults = {
  executors = {
    lua = M.execute_lua_code,
    javascript = M.create_system_executor("node"),
    python = M.create_system_executor("python"),
    rust = M.execute_rust_code,
  },
}

return M
