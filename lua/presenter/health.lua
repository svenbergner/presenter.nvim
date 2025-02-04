local M = {}

M.check = function()
    vim.health.start('presenter report')
    vim.health.ok('presenter is running')
end

return M
