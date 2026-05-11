---@diagnostic disable: undefined-field
local executors = require("presenter.executors")
local presenter = require("presenter")
local eq = assert.are.same

describe("presenter executors", function()
  it("should capture lua print output", function()
    eq({ "hello\t42", "true" }, executors.execute_lua_code({
      code = "print('hello', 42)\nprint(true)",
    }))
  end)

  it("should restore print after executing lua code", function()
    local original_print = print

    executors.execute_lua_code({
      code = "print('before error')\nerror('boom')",
    })

    eq(original_print, print)
  end)

  it("should report invalid lua chunks", function()
    eq({ " <<<BROKEN CODE BLOCK>>>" }, executors.execute_lua_code({
      code = "local =",
    }))
  end)

  it("should keep create_system_executor available from the public module", function()
    eq("function", type(presenter.create_system_executor))
  end)
end)
