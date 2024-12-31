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

--@class presenter.Slide
--@field title string: The title of the slide
--@field body string: The body of the slide

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return presenter.Slides
local parse_slides = function(lines)
  local slides = { slides = {} }
  local current_slide = {
    title = "",
    body = {},
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
      }
    else
      table.insert(current_slide.body, line)
    end
  end

  table.insert(slides.slides, current_slide)
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

-- vim.print(parse_slides({
--   "# Hello",
--   "this is something else",
--   "#World",
--   "this is another thing",
-- }))

-- Remove comment for local testing
M.start_presentation({ bufnr = 3 })

M._parse_slides = parse_slides

return M
