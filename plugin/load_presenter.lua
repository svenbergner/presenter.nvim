vim.api.nvim_create_user_command("PresenterStart", function ()
  require("presenter").start_presentation()
end, {})
