local M = {}

local uv = vim.uv or vim.loop

-- ============================================================================
-- Helper Functions
-- ============================================================================

local function get_git_root()
  return vim.fs.root(0, ".git") or vim.fn.getcwd()
end

local function detect_picker()
  if pcall(require, "snacks") then
    return "snacks"
  elseif pcall(require, "telescope") then
    return "telescope"
  else
    return "standalone"
  end
end

local function collect_untracked_files(git_root, lines_with_numbers, opts, callback)
  vim.fn.jobstart("git ls-files . --exclude-standard --others", {
    stdout_buffered = true,
    on_stdout = vim.schedule_wrap(function(_, output)
      for _, untracked_fname in ipairs(output) do
        if untracked_fname ~= "" then
          local fpath = git_root .. "/" .. untracked_fname
          local stat = uv.fs_lstat(fpath)
          if stat ~= nil and stat.type ~= "link" then
            local ok, contents = pcall(vim.fn.readfile, fpath)
            if ok and contents then
              for line_num, line_content in ipairs(contents) do
                table.insert(lines_with_numbers, fpath .. ":" .. line_num .. ":" .. 1 .. ":" .. line_content)
              end
            end
          end
        end
      end
    end),
    on_exit = vim.schedule_wrap(function()
      callback(lines_with_numbers, opts)
    end),
  })
end

local function collect_added_lines(opts, callback)
  local git_root = get_git_root()
  local lines_with_numbers = {}
  local cur_file = nil
  local cur_line = nil

  vim.fn.jobstart("git diff-index -U0 " .. (opts.git_rev or "HEAD"), {
    on_stdout = vim.schedule_wrap(function(_, output)
      for _, line in ipairs(output) do
        if string.match(line, "^%+%+%+") then
          cur_file = string.sub(line, 6, -1)
        elseif string.match(line, "^@@ %-") then
          cur_line = tonumber(string.gmatch(line, "%+(%d+)")())
        elseif string.match(line, "^%+") and cur_file and cur_line then
          table.insert(
            lines_with_numbers,
            git_root .. "/" .. cur_file .. ":" .. cur_line .. ":" .. 1 .. ":" .. string.sub(line, 2, -1)
          )
          cur_line = cur_line + 1
        end
      end
    end),
    on_exit = vim.schedule_wrap(function()
      collect_untracked_files(git_root, lines_with_numbers, opts, callback)
    end),
  })
end

-- ============================================================================
-- Standalone Backend
-- ============================================================================

local function standalone_display_results(lines_with_numbers, opts)
  if #lines_with_numbers == 0 then
    vim.notify("No added lines found", vim.log.levels.INFO)
    return
  end

  vim.ui.select(lines_with_numbers, {
    prompt = "Added lines (" .. (opts.git_rev or "HEAD") .. "): ",
  }, function(choice, _)
    if choice then
      local path, line_num = choice:match("^([^:]+):(%d+):")
      if path and line_num then
        vim.cmd.edit(path)
        vim.api.nvim_win_set_cursor(0, { tonumber(line_num), 0 })
      end
    end
  end)
end

-- ============================================================================
-- Telescope Backend
-- ============================================================================

local function telescope_display_results(lines_with_numbers, opts)
  if #lines_with_numbers == 0 then
    vim.notify("No added lines found", vim.log.levels.INFO)
    return
  end

  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local telescope_opts = {}
  pickers
    .new(telescope_opts, {
      prompt_title = "Added lines: " .. (opts.git_rev or "HEAD"),
      finder = finders.new_table({
        results = lines_with_numbers,
        entry_maker = function(entry)
          local path, line_num, col, text = entry:match("^([^:]+):(%d+):(%d+):(.*)$")
          return {
            value = entry,
            display = path .. ":" .. line_num .. ":" .. text,
            path = path,
            line_num = tonumber(line_num),
            col = tonumber(col) - 1,
            ordinal = entry,
          }
        end,
      }),
      sorter = conf.generic_sorter(telescope_opts),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd.edit(selection.path)
            vim.api.nvim_win_set_cursor(0, { selection.line_num, selection.col })
          end
        end)
        return true
      end,
    })
    :find()
end

-- ============================================================================
-- Snacks Backend
-- ============================================================================

local function snacks_display_results(lines_with_numbers, opts)
  if #lines_with_numbers == 0 then
    vim.notify("No added lines found", vim.log.levels.INFO)
    return
  end

  local results = {}
  for _, line in ipairs(lines_with_numbers) do
    local path, line_num, col, text = line:match("^([^:]+):(%d+):(%d+):(.*)$")
    if path then
      table.insert(results, {
        file = path,
        pos = { tonumber(line_num), tonumber(col) - 1 },
        text = text,
      })
    end
  end

  local items = {}
  for _, result in ipairs(results) do
    table.insert(items, {
      text = result.file .. ":" .. result.pos[1] .. ":" .. result.text,
      file = result.file,
      pos = result.pos,
    })
  end

  Snacks.picker.pick({
    title = "Added lines: " .. (opts.git_rev or "HEAD"),
    items = items,
    format = "file",
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.cmd.edit(item.file)
        vim.api.nvim_win_set_cursor(0, { item.pos[1], item.pos[2] })
      end
    end,
  })
end

-- ============================================================================
-- Public API
-- ============================================================================

function M.search_in_added(opts)
  opts = opts or {}
  local picker = detect_picker()

  if picker == "snacks" then
    collect_added_lines(opts, snacks_display_results)
  elseif picker == "telescope" then
    collect_added_lines(opts, telescope_display_results)
  else
    collect_added_lines(opts, standalone_display_results)
  end
end

return M
