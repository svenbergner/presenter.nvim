vim.api.nvim_create_user_command("PresenterStart", function ()
  -- Easy Reloading
  package.loaded["presenter"] = nil

  require("presenter").start_presentation()
end, {})
