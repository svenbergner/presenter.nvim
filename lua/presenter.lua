local M = {}

local function create_floating_window(config, enter)
  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
  local win = vim.api.nvim_open_win(buf, enter, config)

  return { buf = buf, win = win }
end

M.setup = function()
  -- nothing
end

---@class presenter.Slides
---@fields slides presenter.Slides[]: The slides of the file

---@class presenter.Slide
---@field title string: The title of the slide
---@field body string[]: The body of the slide
---@field blocks presenter.blocks[]: A codeblock inside of a slide

---@class presenter.Block
---@field language string: The language of the block
---@field code string: The code inside of the block

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return presenter.Slides
local parse_slides = function(lines)
  local slides = { slides = {} }
  local current_slide = {
    title = "",
    body = {},
    blocks = {},
  }

  local separator = "^#"

  for _, line in ipairs(lines) do
    if line:find(separator) then
      if #current_slide.title > 0 then
        table.insert(slides.slides, current_slide)
      end

      current_slide = {
        title = line:sub(3),
        body = {},
        blocks = {},
      }
    else
      table.insert(current_slide.body, line)
    end
  end

  table.insert(slides.slides, current_slide)

  for _, slide in ipairs(slides.slides) do
    local block = {
      language = nil,
      code = "",
    }
    local inside_block = false
    for _, line in ipairs(slide.body) do
      if line:find("^```") then
        if inside_block then
          inside_block = false
          block.code = vim.trim(block.code)
          table.insert(slide.blocks, block)
        else
          inside_block = true
          block.language = line:sub(4)
        end
      else
        if inside_block then
          block.code = block.code .. line .. "\n"
        end
      end
    end
  end

  return slides
end

local create_window_configurations = function()
  local width = vim.o.columns
  local height = vim.o.lines

  local header_height = 1 + 2                                    -- 1 + border
  local footer_height = 1                                        -- 1, no border
  local body_height = height - header_height - footer_height - 3 -- for our own border

  return {
    background = {
      relative = "editor",
      width = width,
      height = height,
      style = "minimal",
      col = 0,
      row = 0,
      zindex = 1,
    },
    header = {
      relative = "editor",
      width = width - 8,
      height = 1,
      style = "minimal",
      border = "rounded",
      col = 4,
      row = 0,
      zindex = 2,
    },
    body = {
      relative = "editor",
      width = width - 8,
      height = body_height,
      style = "minimal",
      border = { " ", " ", " ", " ", " ", " ", " ", " " },
      col = 8,
      row = 4,
    },
    footer = {
      relative = "editor",
      width = width - 8,
      height = 1,
      style = "minimal",
      -- border = { " ", " ", " ", " ", " ", " ", " ", " " },
      col = 0,
      row = height - footer_height,
      zindex = 2,

    },
  }
end

local state = {
  parsed = {
    slides = {}
  },
  current_slide = 1,
  current_file = "",
  floats = {}
}

local foreach_float = function(cb)
  for name, float in pairs(state.floats) do
    cb(name, float)
  end
end

local presenter_keymap = function(mode, key, callback)
  vim.keymap.set(mode, key, callback, {
    buffer = state.floats.body.buf
  })
end

M.start_presentation = function(opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or 0

  local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
  state.parsed = parse_slides(lines)
  state.current_slide = 1
  state.current_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ":t")

  local windows = create_window_configurations()
  state.floats.background = create_floating_window(windows.background)
  state.floats.header = create_floating_window(windows.header)
  state.floats.body = create_floating_window(windows.body, true)
  state.floats.footer = create_floating_window(windows.footer)

  foreach_float(function(_, float)
    vim.bo[float.buf].filetype = "markdown"
  end)

  local set_slide_content = function(idx)
    local width = vim.o.columns

    local slide = state.parsed.slides[idx]

    local padding = string.rep(" ", math.floor((width - #slide.title) / 2))
    local title = padding .. slide.title
    vim.api.nvim_buf_set_lines(state.floats.header.buf, 0, -1, false, { title })
    vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, slide.body)


    local footer = string.format(
      "  %d / %d | %s",
      state.current_slide,
      #state.parsed.slides,
      state.current_file
    )
    vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, { footer })
  end

  presenter_keymap('n', 'n', function()
    state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
    set_slide_content(state.current_slide)
  end)

  presenter_keymap('n', '<CR>', function()
    state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
    set_slide_content(state.current_slide)
  end)

  presenter_keymap('n', '<space>', function()
    state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
    set_slide_content(state.current_slide)
  end)

  presenter_keymap('n', 'p', function()
    state.current_slide = math.max(state.current_slide - 1, 1)
    set_slide_content(state.current_slide)
  end)

  presenter_keymap('n', '<BS>', function()
    state.current_slide = math.max(state.current_slide - 1, 1)
    set_slide_content(state.current_slide)
  end)

  presenter_keymap('n', 'q', function()
    -- vim.api.nvim_win_close(state.floats.header.win, true)
    vim.api.nvim_win_close(state.floats.body.win, true)
  end)

  presenter_keymap('n', 'X', function()
    local slide = state.parsed.slides[state.current_slide]
    local block = slide.blocks[1]
    if not block then
      print("No code blocks on this page")
      return
    end

    -- Overwrite the default print function to capture all of the output
    -- Store the original print function
    local original_print = print

    -- Table to store the output of the print function
    local output = { "", "# Code", "", "```" .. block.language }
    vim.list_extend(output, vim.split(block.code, "\n"))
    table.insert(output, "```")

    -- Redefine the print function
    print = function(...)
      local args = { ... }
      local message = table.concat(vim.tbl_map(tostring, args), "\t")
      table.insert(output, message)
    end

    local code = block.code
    local chunk = loadstring(code)

    -- Call the provided code block
    pcall(function()
      table.insert(output, "")
      table.insert(output, "# Output")
      table.insert(output, "")
      if not chunk then
        table.insert(output, "  <<<BROKEN CODE BLOCK>>>")
      else
        chunk()
      end
    end)

    -- Restore the original print function
    print = original_print

    local buf = vim.api.nvim_create_buf(false, true)
    local temp_width = math.floor(vim.o.columns * 0.8)
    local temp_height = math.floor(vim.o.lines * 0.8)
    local temp_row = math.floor((vim.o.lines - temp_height) / 2)
    local temp_col = math.floor((vim.o.columns - temp_width) / 2)
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      width = temp_width,
      height = temp_height,
      row = temp_row,
      col = temp_col,
    })

    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
  end)

  local restore = {
    cmdheight = {
      original = vim.o.cmdheight,
      presenting = 0,
    },
  }

  -- Set the options we want for the presentation
  for option, config in pairs(restore) do
    vim.opt[option] = config.presenting
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = state.floats.body.buf,
    callback = function()
      -- Restore the original options when we are done with the presentation
      for option, config in pairs(restore) do
        vim.opt[option] = config.original
      end

      foreach_float(function(_, float)
        pcall(vim.api.nvim_win_close, float.win, true)
      end)
    end
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("presenter-resized", {}),
    callback = function()
      if not vim.api.nvim_win_is_valid(state.floats.body.win) or state.floats.body.win == nil then
        return
      end

      local updated = create_window_configurations()
      foreach_float(function(name, _)
        vim.api.nvim_win_set_config(state.floats[name].win, updated[name])
      end)

      -- Re-calculates current slides contents
      set_slide_content(state.current_slide)
    end,
  })

  set_slide_content(state.current_slide)
end

M._parse_slides = parse_slides

return M
