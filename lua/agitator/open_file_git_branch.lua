local utils = require("agitator.utils")

local M = {}

-- ============================================================================
-- Helper Functions
-- ============================================================================

local function detect_picker()
  if pcall(require, "snacks") then
    return "snacks"
  elseif pcall(require, "telescope") then
    return "telescope"
  else
    return "standalone"
  end
end

-- ============================================================================
-- Standalone Implementation
-- ============================================================================

local function standalone_pick_branch(cb)
  local branches = {}
  local handle = io.popen("git branch --sort=-committerdate -a 2>/dev/null")
  if not handle then
    vim.notify("Failed to get branches", vim.log.levels.ERROR)
    return
  end
  for line in handle:lines() do
    table.insert(branches, line:gsub("^%*?%s+", ""))
  end
  handle:close()

  if #branches == 0 then
    vim.notify("No branches found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(branches, { prompt = "Branch: " }, function(choice)
    if choice then
      vim.schedule(function()
        cb(choice)
      end)
    end
  end)
end

local function standalone_pick_file_from_branch(branch)
  local files = {}
  local handle = io.popen("git ls-tree -r --name-only " .. vim.fn.shellescape(branch) .. " 2>/dev/null")
  if not handle then
    vim.notify("Failed to list files from branch", vim.log.levels.ERROR)
    return
  end
  for line in handle:lines() do
    if line ~= "" then
      table.insert(files, line)
    end
  end
  handle:close()

  if #files == 0 then
    vim.notify("No files found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(files, { prompt = "File: " }, function(choice)
    if choice then
      vim.cmd("enew")
      utils.open_file_branch(branch, choice)
    end
  end)
end

local function standalone_search_in_branch(branch)
  local word = vim.fn.expand("<cword>")
  local cmd = "git grep -n " .. vim.fn.shellescape(word) .. " " .. vim.fn.shellescape(branch)
  local handle = io.popen(cmd .. " 2>/dev/null")
  if not handle then
    vim.notify("Failed to search in branch", vim.log.levels.ERROR)
    return
  end

  local results = {}
  for line in handle:lines() do
    if line ~= "" then
      table.insert(results, line)
    end
  end
  handle:close()

  if #results == 0 then
    vim.notify("No matches found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(results, { prompt = "Match: " }, function(choice)
    if choice then
      -- Format: path:line:text
      local path, line_str = choice:match("^([^:]+):(%d+):")
      if path and line_str then
        vim.cmd("enew")
        utils.open_file_branch(branch, path)
        vim.cmd(":" .. line_str)
      end
    end
  end)
end

-- ============================================================================
-- Telescope Implementation
-- ============================================================================

local function telescope_pick_branch(cb)
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local opts = {}
  pickers
    .new(opts, {
      prompt_title = "branch",
      finder = finders.new_oneshot_job({ "git", "branch", "--sort=-committerdate", "-a" }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          local branch = selection[1]:gsub("^%*?%s+", "")
          vim.schedule(function()
            cb(branch)
          end)
        end)
        return true
      end,
    })
    :find()
end

local function telescope_pick_file_from_branch(branch)
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local relative_fname = utils.get_relative_fname()
  local opts = {}
  opts.initial_mode = "insert"
  opts.default_text = relative_fname

  local function open_branch_action(prompt_bufnr, action)
    actions.close(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    vim.api.nvim_command(action)
    utils.open_file_branch(branch, selection[1])
  end

  pickers
    .new(opts, {
      prompt_title = "filename",
      finder = finders.new_oneshot_job({ "git", "ls-tree", "-r", "--name-only", branch }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          open_branch_action(prompt_bufnr, "enew")
        end)
        actions.select_vertical:replace(function()
          open_branch_action(prompt_bufnr, "vnew")
        end)
        return true
      end,
    })
    :find()
end

local function telescope_search_in_branch(branch)
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local opts = {}
  opts.initial_mode = "insert"
  opts.default_text = vim.fn.expand("<cword>")

  pickers
    .new(opts, {
      prompt_title = "search expression",
      finder = finders.new_job(function(prompt)
        return { "git", "grep", "-n", prompt, branch }
      end),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          -- Format: path:line:text
          local path_line_string = selection[1]:gsub("^[^:]+:", "")
          local path = path_line_string:gsub(":.*$", "")
          local line = path_line_string:gsub("^[^:]+:", ""):gsub(":.*$", "")
          vim.api.nvim_command("enew")
          utils.open_file_branch(branch, path)
          vim.cmd(":" .. line)
        end)
        return true
      end,
    })
    :find()
end

-- ============================================================================
-- Snacks Implementation
-- ============================================================================

local function snacks_pick_branch(cb)
  Snacks.picker.pick({
    title = "Branch",
    finder = function(_, ctx)
      local Proc = require("snacks.picker.source.proc")
      return Proc.proc({
        cmd = "git",
        args = { "branch", "--sort=-committerdate", "-a" },
        transform = function(item)
          item.text = item.text:gsub("^%*?%s+", "")
        end,
      }, ctx)
    end,
    format = "text",
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          cb(item.text)
        end)
      end
    end,
  })
end

local function snacks_pick_file_from_branch(branch)
  local relative_fname = utils.get_relative_fname()

  local function open_branch_action(picker, item, action)
    picker:close()
    local cmd = action and action.cmd or "enew"
    if cmd == "split" then
      vim.cmd("new")
    elseif cmd == "vsplit" then
      vim.cmd("vnew")
    elseif cmd == "tab" then
      vim.cmd("tabnew")
    else
      vim.cmd("enew")
    end
    utils.open_file_branch(branch, item.text)
  end

  Snacks.picker.pick({
    title = "File: " .. branch,
    pattern = relative_fname,
    branch = branch,
    finder = function(_, ctx)
      local Proc = require("snacks.picker.source.proc")
      return Proc.proc({
        cmd = "git",
        args = { "ls-tree", "-r", "--name-only", branch },
      }, ctx)
    end,
    format = "text",
    confirm = open_branch_action,
    actions = {
      edit_split = function(picker, item)
        open_branch_action(picker, item, { cmd = "split" })
      end,
      edit_vsplit = function(picker, item)
        open_branch_action(picker, item, { cmd = "vsplit" })
      end,
      tab = function(picker, item)
        open_branch_action(picker, item, { cmd = "tab" })
      end,
    },
    win = {
      input = {
        keys = {
          ["<c-s>"] = { "edit_split", mode = { "n", "i" } },
          ["<c-v>"] = { "edit_vsplit", mode = { "n", "i" } },
          ["<c-t>"] = { "tab", mode = { "n", "i" } },
        },
      },
    },
  })
end

local function snacks_search_in_branch(branch)
  local word = vim.fn.expand("<cword>")
  local rev = branch:gsub("^remotes/", "")

  Snacks.picker.pick({
    title = "Search: " .. rev,
    search = word,
    pattern = "",
    branch = rev,
    live = true,
    supports_live = true,
    finder = function(_, ctx)
      if ctx.filter.search == "" then
        return function() end
      end
      local Proc = require("snacks.picker.source.proc")
      return Proc.proc({
        cmd = "git",
        args = { "grep", "--line-number", "--column", "--no-color", "-I", ctx.filter.search, rev },
        transform = function(item)
          local file, line, col, text = item.text:match("^(.+):(%d+):(%d+):(.*)$")
          if file then
            item.file = file
            item.pos = { tonumber(line), tonumber(col) - 1 }
            item.line = text
            item.text = file .. ":" .. line .. ":" .. text
            return
          end
          local file2, line2, text2 = item.text:match("^([^:]+):(%d+):(.*)$")
          if not file2 then
            return false
          end
          item.file = file2
          item.pos = { tonumber(line2), 0 }
          item.line = text2
          item.text = file2 .. ":" .. line2 .. ":" .. text2
        end,
      }, ctx)
    end,
    format = "file",
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.cmd("enew")
        utils.open_file_branch(rev, item.file)
        vim.cmd(":" .. item.pos[1])
      end
    end,
  })
end

-- ============================================================================
-- Public API
-- ============================================================================

function M.open_file_git_branch()
  local picker = detect_picker()
  local pick_branch_fn
  local pick_file_fn

  if picker == "snacks" then
    pick_branch_fn = snacks_pick_branch
    pick_file_fn = snacks_pick_file_from_branch
  elseif picker == "telescope" then
    pick_branch_fn = telescope_pick_branch
    pick_file_fn = telescope_pick_file_from_branch
  else
    pick_branch_fn = standalone_pick_branch
    pick_file_fn = standalone_pick_file_from_branch
  end

  pick_branch_fn(pick_file_fn)
end

function M.search_git_branch()
  local picker = detect_picker()
  local pick_branch_fn
  local search_fn

  if picker == "snacks" then
    pick_branch_fn = snacks_pick_branch
    search_fn = snacks_search_in_branch
  elseif picker == "telescope" then
    pick_branch_fn = telescope_pick_branch
    search_fn = telescope_search_in_branch
  else
    pick_branch_fn = standalone_pick_branch
    search_fn = standalone_search_in_branch
  end

  pick_branch_fn(search_fn)
end

return M
