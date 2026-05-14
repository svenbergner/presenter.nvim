local M = {}

local create_floating_window = require("presenter.tools").create_floating_window
local section_query = vim.treesitter.query.parse("markdown", [[(section) @section]])
local codeblock_query = vim.treesitter.query.parse("markdown", [[(fenced_code_block) @codeblock]])

-- TODO: This was returning goofy stuff
-- local language_query =
--   vim.treesitter.query.parse("markdown", [[(fenced_code_block (info_string (language) @language))]])

local defaults = require("presenter.executors").defaults
M.create_system_executor = require("presenter.executors").create_system_executor

local default_options = vim.tbl_deep_extend("force", {
   syntax = {
      comment = "%%",
      stop = "<!%-%-%s*stop%s*%-%->",
   },
}, defaults)

---@class presenter.Options
---@field executors table<string, function>: The executors for the different languages
---@field syntax presenter.SyntaxOptions: The syntax for the plugin

---@class presenter.SyntaxOptions
---@field comment string?: The prefix for comments, will skip lines that start with this
---@field stop string?: The stop comment, will stop slide when found. Note: Is a Lua Pattern

---@type presenter.Options
local options = {
   syntax = {
      comment = "%%",
      stop = "<!%-%-%s*stop%s*%-%->",
   },
   executors = defaults.executors,
}

--- Setup the plugin
--- @param opts presenter.Options
M.setup = function(opts)
   options = vim.tbl_deep_extend("force", default_options, opts or {})
end

---@class presenter.Slides
---@field slides presenter.Slide[]: The slides of the file
---@field metadata presenter.Metadata: Metadata for the presentation

---@class presenter.Metadata
---@field title string?: The title of the presentation
---@field presenter string?: The presenter of the presentation
---@field date string?: The date of the presentation
---@field figlet string?: Whether to render slide headers through figlet
---@field figlet_font string?: The figlet font to use for slide headers
---@field figlet_width string?: The output width passed to figlet
---@field figlet_kerning string?: Whether to use figlet kerning mode

---@class presenter.Slide
---@field title string: The title of the slide
---@field body string[]: The body of the slide
---@field blocks presenter.Block[]: A codeblock inside of a slide

---@class presenter.Block
---@field language string: The language of the block
---@field code string: The code inside of the block
---@field start_row integer: The start row of the codeblock
---@field end_row integer: The end row of the codeblock

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return presenter.Slides
local parse_slides = function(lines)
   local metadata = {}
   local content_lines = lines

   if lines[1] == "---" then
      local parsed_metadata = {}
      for idx = 2, #lines do
         if lines[idx] == "---" then
            metadata = parsed_metadata
            content_lines = vim.list_slice(lines, idx + 1)
            break
         end

         local key, value = lines[idx]:match("^%s*([%w_-]+)%s*:%s*(.-)%s*$")
         if key and value then
            parsed_metadata[key] = value
         end
      end
   end

   local contents = table.concat(content_lines, "\n") .. "\n"
   local parser = vim.treesitter.get_string_parser(contents, "markdown")
   local root = parser:parse()[1]:root()

   local slides = { slides = {}, metadata = metadata }

   local create_empty_slide = function()
      return { title = "", body = {}, blocks = {} }
   end

   local parse_title = function(line)
      return line:gsub("^%s*#+%s+", "")
   end

   local add_line_to_block = function(slide, line)
      if not line then
         return
      end

      -- Trim trailing whitespace, it can have weird highlighting and whatnot
      line = line:gsub("%s*$", "")
      table.insert(slide.body, line)
   end

   local get_block = function(codeblocks, idx)
      for _, codeblock in ipairs(codeblocks) do
         if idx >= codeblock.start_row and idx <= codeblock.end_row then
            return codeblock
         end
      end

      return nil
   end

   local current_slide = create_empty_slide()
   for _, node in section_query:iter_captures(root, contents, 0, -1) do
      if #current_slide.title > 0 then
         table.insert(slides.slides, current_slide)
         current_slide = create_empty_slide()
      end

      local start_row, _, end_row, _ = node:range()
      current_slide.title = parse_title(content_lines[start_row + 1])
      local codeblocks = vim.iter(codeblock_query:iter_captures(root, contents, start_row, end_row))
         :map(function(_, n)
            local s, _, e, _ = n:range()
            local language = vim.trim(string.sub(content_lines[s + 1], 4))
            return {
               language = language,
               code = table.concat(vim.list_slice(content_lines, s + 2, e - 1), "\n"),
               start_row = s + 1,
               end_row = e,
            }
         end)
         :totable()

      local comment = options.syntax.comment
      local stop = options.syntax.stop

      local process_line = function(idx)
         local line = content_lines[idx]
         local block = get_block(codeblocks, idx)

         -- Only do our comments/splits/etc if we are not in a codeblock
         if not block then
            -- Skip comment lines
            if comment and vim.startswith(line, comment) then
               return
            end

            -- Split on `stop` comments
            if stop and line:find(stop) then
               line = line:gsub(stop, "")
               add_line_to_block(current_slide, line)
               table.insert(slides.slides, current_slide)
               current_slide = vim.deepcopy(current_slide)
               return
            end

            return add_line_to_block(current_slide, line)
         end

         -- Only add code blocks to the current slide if we have
         -- actually reached them (this could not happen because of stop comments)
         if idx == block.start_row then
            table.insert(current_slide.blocks, block)
         end

         -- GIVE ME THE CODE AND GIVE IT TO ME RAW
         add_line_to_block(current_slide, content_lines[idx])
      end

      -- Process the lines: Add one for row->line, add one to skip the header
      local start_of_section = start_row + 2
      for idx = start_of_section, end_row do
         process_line(idx)
      end
   end

   -- Add the last slide, won't happen in the loop
   --  Could probably switch to do-while loop and make Prime happy,
   --  but that would make me sad.
   table.insert(slides.slides, current_slide)

   return slides
end

local format_footer = function(parsed, current_slide, current_file)
   local metadata = parsed.metadata or {}
   local parts = {
      string.format("%d / %d", current_slide, #parsed.slides),
   }

   if metadata.title and metadata.title ~= "" then
      table.insert(parts, metadata.title)
   end

   if metadata.presenter and metadata.presenter ~= "" then
      table.insert(parts, metadata.presenter)
   end

   if metadata.date and metadata.date ~= "" then
      table.insert(parts, metadata.date)
   end

   if #parts == 1 then
      table.insert(parts, current_file)
   end

   return "  " .. table.concat(parts, " | ")
end

local is_truthy_metadata = function(value)
   if not value then
      return false
   end

   value = tostring(value):lower()
   return value == "true" or value == "yes" or value == "on" or value == "1"
end

local should_use_figlet = function(metadata)
   metadata = metadata or {}
   if metadata.figlet ~= nil then
      return is_truthy_metadata(metadata.figlet)
   end

   return metadata.figlet_font ~= nil or metadata.figlet_width ~= nil or metadata.figlet_kerning ~= nil
end

local build_figlet_args = function(metadata, title)
   metadata = metadata or {}
   local args = { "figlet" }

   if metadata.figlet_font and metadata.figlet_font ~= "" then
      vim.list_extend(args, { "-f", metadata.figlet_font })
   end

   if metadata.figlet_width and metadata.figlet_width ~= "" then
      local width = tonumber(metadata.figlet_width)
      if width and width > 0 then
         vim.list_extend(args, { "-w", tostring(math.floor(width)) })
      end
   end

   if is_truthy_metadata(metadata.figlet_kerning) then
      table.insert(args, "-k")
   end

   table.insert(args, title)
   return args
end

local center_lines = function(lines, width)
   local max_line_width = vim
      .iter(lines)
      :fold(0, function(max_width, line)
         return math.max(max_width, #line)
      end)

   local padding = string.rep(" ", math.max(math.floor((width - max_line_width) / 2), 0))

   return vim
      .iter(lines)
      :map(function(line)
         return padding .. line
      end)
      :totable()
end

local format_header = function(title, metadata, width, systemlist)
   if not should_use_figlet(metadata) or (not systemlist and vim.fn.executable("figlet") ~= 1) then
      return center_lines({ title }, width)
   end

   local ok, lines = pcall(systemlist or vim.fn.systemlist, build_figlet_args(metadata, title))
   if not ok or (not systemlist and vim.v.shell_error ~= 0) or not lines or #lines == 0 then
      return center_lines({ title }, width)
   end

   while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
   end

   if #lines == 0 then
      return center_lines({ title }, width)
   end

   return center_lines(lines, width)
end

local create_window_configurations = function(header_height)
   header_height = math.max(header_height or 1, 1)

   local width = vim.o.columns
   local height = vim.o.lines

   local header_window_height = header_height + 2 -- content + border
   local footer_height = 1 -- 1, no border
   local body_height = math.max(height - header_window_height - footer_height - 3, 1) -- for our own border

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
         height = header_height,
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
         row = header_window_height + 1,
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
      slides = {},
   },
   current_slide = 1,
   current_file = "",
   floats = {},
}

local foreach_float = function(cb)
   for name, float in pairs(state.floats) do
      cb(name, float)
   end
end

local presenter_keymap = function(mode, key, callback)
   vim.keymap.set(mode, key, callback, {
      buffer = state.floats.body.buf,
   })
end

M.start_presentation = function(opts)
   opts = opts or {}
   opts.bufnr = opts.bufnr or 0

   local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
   state.parsed = parse_slides(lines)
   state.current_slide = 1
   state.current_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ":t")

   local windows = create_window_configurations(1)
   state.floats.background = create_floating_window(windows.background)
   state.floats.header = create_floating_window(windows.header)
   state.floats.footer = create_floating_window(windows.footer)
   state.floats.body = create_floating_window(windows.body, true)

   foreach_float(function(_, float)
      vim.bo[float.buf].filetype = "markdown"
   end)

   local set_slide_content = function(idx)
      local width = vim.o.columns

      local slide = state.parsed.slides[idx]

      local title = format_header(slide.title, state.parsed.metadata, width - 8)
      local updated = create_window_configurations(#title)
      vim.api.nvim_win_set_config(state.floats.header.win, updated.header)
      vim.api.nvim_win_set_config(state.floats.body.win, updated.body)

      vim.api.nvim_buf_set_lines(state.floats.header.buf, 0, -1, false, title)
      vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, slide.body)

      local footer = format_footer(state.parsed, state.current_slide, state.current_file)
      vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, { footer })
   end

   presenter_keymap("n", "n", function()
      state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
      set_slide_content(state.current_slide)
   end)

   presenter_keymap("n", "<CR>", function()
      state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
      set_slide_content(state.current_slide)
   end)

   presenter_keymap("n", "<Space>", function()
      state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
      set_slide_content(state.current_slide)
   end)

   presenter_keymap("n", "<PageDown>", function()
      state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
      set_slide_content(state.current_slide)
   end)

   presenter_keymap("n", "p", function()
      state.current_slide = math.max(state.current_slide - 1, 1)
      set_slide_content(state.current_slide)
   end)

   presenter_keymap("n", "<BS>", function()
      state.current_slide = math.max(state.current_slide - 1, 1)
      set_slide_content(state.current_slide)
   end)

   presenter_keymap("n", "<PageUp>", function()
      state.current_slide = math.max(state.current_slide - 1, 1)
      set_slide_content(state.current_slide)
   end)

   presenter_keymap("n", "q", function()
      -- vim.api.nvim_win_close(state.floats.header.win, true)
      vim.api.nvim_win_close(state.floats.body.win, true)
   end)

   presenter_keymap("n", "X", function()
      local slide = state.parsed.slides[state.current_slide]
      local block = slide.blocks[1]
      if not block then
         print("No code blocks on this page")
         return
      end

      local executor = options.executors[block.language]
      if not executor then
         print("No valid executor for this language: " .. block.language)
         return
      end

      -- Table to capture print messages
      local output = { "# Code", "", "```" .. block.language }
      vim.list_extend(output, vim.split(block.code, "\n"))
      table.insert(output, "```")

      table.insert(output, "")
      table.insert(output, "# Output")
      table.insert(output, "")
      table.insert(output, "```")
      vim.list_extend(output, executor(block))
      table.insert(output, "```")

      local buf = vim.api.nvim_create_buf(false, true)
      local temp_width = math.floor(vim.o.columns * 0.8)
      local temp_height = math.floor(vim.o.lines * 0.8)
      local temp_row = math.floor((vim.o.lines - temp_height) / 2)
      local temp_col = math.floor((vim.o.columns - temp_width) / 2)
      vim.api.nvim_open_win(buf, true, {
         relative = "editor",
         style = "minimal",
         noautocmd = true,
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
         present = 0,
      },
      guicursor = {
         original = vim.o.guicursor,
         present = "n:NormalFloat",
      },
      wrap = {
         original = vim.o.wrap,
         present = true,
      },
      breakindent = {
         original = vim.o.breakindent,
         present = true,
      },
      breakindentopt = {
         original = vim.o.breakindentopt,
         present = "list:-1",
      },
   }

   -- Set the options we want for the presentation
   for option, config in pairs(restore) do
      vim.opt[option] = config.present
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
      end,
   })

   vim.api.nvim_create_autocmd("VimResized", {
      group = vim.api.nvim_create_augroup("presenter-resized", {}),
      callback = function()
         if not vim.api.nvim_win_is_valid(state.floats.body.win) or state.floats.body.win == nil then
            return
         end

         local title = format_header(state.parsed.slides[state.current_slide].title, state.parsed.metadata, vim.o.columns - 8)
         local updated = create_window_configurations(#title)
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
M._format_footer = format_footer
M._format_header = format_header
M._build_figlet_args = build_figlet_args

return M
