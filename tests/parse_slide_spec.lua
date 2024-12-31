---@diagnostic disable: undefined-field
local parse = require("presenter")._parse_slides
local eq = assert.are.same

describe("presenter.parse_slides", function()
  it("should parse an empty file", function()
    eq({
      slides = {
        {
          title = '',
          body = {},
          notes = {},
          tags = {},
        }
      }
    }, parse({}))
  end)

  it("should parse an file with one slide", function()
    eq({
      slides = {
        {
          title = "This is the first slide",
          body = { "This is the body" },
          notes = {},
          tags = {},
        }
      }
    }, parse({
      "# This is the first slide",
      "This is the body"
    }))
  end)
end)
