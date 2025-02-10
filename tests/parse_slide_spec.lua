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
          blocks = {},
        }
      }
    }, parse({""}))
  end)

  it("should parse an file with one slide", function()
    eq({
      slides = {
        {
          title = "This is the first slide",
          body = { "This is the body" },
          blocks = {},
        }
      }
    }, parse({
      "This is the first slide",
      "This is the body"
    }))
  end)

  it("should parse an file with one slide and a block", function()
    local results = parse({
      "This is the first slide",
      "This is the body",
      "```lua",
      "print('hi')",
      "```",
    })

    -- Should only have one slide
    eq(1, #results.slides)

    local slide = results.slides[1]
    eq("This is the first slide", slide.title)
    eq({ "This is the body",
      "```lua",
      "print('hi')",
      "```",
    }, slide.body)

    local block = {
      language = "lua",
      code = "print('hi')",
      start_row = 3,
      end_row = 5,
    }

    eq(block, slide.blocks[1])
  end)
end)
