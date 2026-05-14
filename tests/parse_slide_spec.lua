---@diagnostic disable: undefined-field
local presenter = require("presenter")
local parse = presenter._parse_slides
local eq = assert.are.same

describe("presenter.parse_slides", function()
  before_each(function()
    presenter.setup({})
  end)

  it("should parse an empty file", function()
    eq({
      metadata = {},
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
      metadata = {},
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

  it("should parse multiple heading sections as slides", function()
    eq({
      metadata = {},
      slides = {
        {
          title = "First",
          body = { "First body" },
          blocks = {},
        },
        {
          title = "Second",
          body = { "Second body" },
          blocks = {},
        },
      }
    }, parse({
      "# First",
      "First body",
      "# Second",
      "Second body",
    }))
  end)

  it("should remove markdown heading markers from slide titles", function()
    local results = parse({
      "### Deep heading",
      "Body",
    })

    eq("Deep heading", results.slides[1].title)
  end)

  it("should skip presenter comments outside of code blocks", function()
    eq({
      metadata = {},
      slides = {
        {
          title = "Slide",
          body = { "Visible" },
          blocks = {},
        },
      }
    }, parse({
      "# Slide",
      "%% hidden presenter note",
      "Visible",
    }))
  end)

  it("should keep presenter comments inside code blocks", function()
    local results = parse({
      "# Slide",
      "```lua",
      "%% this is lua input, not a presenter comment",
      "```",
    })

    eq({
      "```lua",
      "%% this is lua input, not a presenter comment",
      "```",
    }, results.slides[1].body)
    eq("%% this is lua input, not a presenter comment", results.slides[1].blocks[1].code)
  end)

  it("should split stop comments into incremental slides", function()
    eq({
      metadata = {},
      slides = {
        {
          title = "Slide",
          body = { "First", "" },
          blocks = {},
        },
        {
          title = "Slide",
          body = { "First", "", "Second" },
          blocks = {},
        },
      }
    }, parse({
      "# Slide",
      "First",
      "<!-- stop -->",
      "Second",
    }))
  end)

  it("should not split stop comments inside code blocks", function()
    local results = parse({
      "# Slide",
      "```html",
      "<!-- stop -->",
      "```",
    })

    eq(1, #results.slides)
    eq({
      "```html",
      "<!-- stop -->",
      "```",
    }, results.slides[1].body)
  end)

  it("should preserve defaults when setup is called with an empty table", function()
    presenter.setup({})

    eq({
      metadata = {},
      slides = {
        {
          title = "Slide",
          body = { "Visible" },
          blocks = {},
        },
      }
    }, parse({
      "# Slide",
      "%% hidden presenter note",
      "Visible",
    }))
  end)

  it("should merge custom syntax", function()
    presenter.setup({
      syntax = {
        comment = "//",
        stop = "^---$",
      },
      executors = {
        custom = function()
          return { "custom" }
        end,
      },
    })

    local results = parse({
      "# Slide",
      "// hidden presenter note",
      "First",
      "---",
      "Second",
    })

    eq(2, #results.slides)
    eq({ "First", "" }, results.slides[1].body)
    eq({ "First", "", "Second" }, results.slides[2].body)
  end)

  it("should parse presentation metadata from a header", function()
    local results = parse({
      "---",
      "title: Parser Deep Dive",
      "presenter: Sven Bergner",
      "date: 2026-05-11",
      "---",
      "# Intro",
      "Welcome",
    })

    eq({
      title = "Parser Deep Dive",
      presenter = "Sven Bergner",
      date = "2026-05-11",
    }, results.metadata)
    eq(1, #results.slides)
    eq("Intro", results.slides[1].title)
    eq({ "Welcome" }, results.slides[1].body)
  end)

  it("should ignore malformed metadata lines in the header", function()
    local results = parse({
      "---",
      "title: Valid title",
      "this is not metadata",
      "---",
      "# Intro",
    })

    eq({ title = "Valid title" }, results.metadata)
    eq("Intro", results.slides[1].title)
  end)

  it("should not parse an unclosed header as metadata", function()
    local results = parse({
      "---",
      "title: Not metadata",
      "# Intro",
    })

    eq({}, results.metadata)
    eq("---", results.slides[1].title)
  end)
end)

describe("presenter footer", function()
  it("should include presentation metadata when available", function()
    eq("  2 / 5 | Parser Deep Dive | Sven Bergner | 2026-05-11", presenter._format_footer({
      metadata = {
        title = "Parser Deep Dive",
        presenter = "Sven Bergner",
        date = "2026-05-11",
      },
      slides = { {}, {}, {}, {}, {} },
    }, 2, "fallback.md"))
  end)

  it("should fall back to the current file when no metadata is available", function()
    eq("  1 / 3 | slides.md", presenter._format_footer({
      metadata = {},
      slides = { {}, {}, {} },
    }, 1, "slides.md"))
  end)
end)

describe("presenter header", function()
  it("should center plain headers when figlet is disabled", function()
    eq({ "  Intro" }, presenter._format_header("Intro", {}, 10))
  end)

  it("should build figlet args from presentation metadata", function()
    eq({
      "figlet",
      "-f",
      "slant",
      "-w",
      "100",
      "-k",
      "Intro",
    }, presenter._build_figlet_args({
      figlet_font = "slant",
      figlet_width = "100",
      figlet_kerning = "true",
    }, "Intro"))
  end)

  it("should render and center figlet headers when enabled", function()
    local function systemlist(args)
      eq({ "figlet", "-f", "standard", "Intro" }, args)
      return { " ___", "|_ _|", "" }
    end

    eq({
      "   ___",
      "  |_ _|",
    }, presenter._format_header("Intro", {
      figlet = "true",
      figlet_font = "standard",
    }, 10, systemlist))
  end)
end)
