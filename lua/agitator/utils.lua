local function get_cwd()
  local cwd = vim.fn.getcwd()
  if vim.fn.has("win32") then
    return cwd:gsub("\\", "/")
  else
    return cwd
  end
end

function commit_head_of_branch(branch)
  return vim
    .system({ "git", "log", branch, "-n1", '--pretty=format:"%h"', "--no-patch" })
    :wait()
    .stdout
    -- surely there's a better way... shouldn't get these quotes in the first place
    :gsub('"', "")
end

function git_root_folder()
  return vim.trim(vim.system({ "git", "rev-parse", "--show-toplevel" }):wait().stdout)
end

-- https://stackoverflow.com/a/34953646/516188
local function escape_pattern(text)
  return text:gsub("([^%w])", "%%%1")
end

-- https://vi.stackexchange.com/a/3749/38754
local function open_file_branch(branch, fname)
  vim.api.nvim_exec2("silent r! git show " .. branch .. ":./" .. fname, { output = false })
  vim.api.nvim_command("1d")
  local fname_without_path = fname:match("([^/]+)$")
  local base_bufcmd = "silent file [" .. branch .. "] " .. fname_without_path
  local commit = commit_head_of_branch(branch)
  local path_in_git_prj = (get_cwd() .. "/" .. fname):gsub(escape_pattern(git_root_folder()) .. "/", "")
  vim.b.agitator_commit = commit
  vim.b.agitator_path_in_git_prj = path_in_git_prj
  -- if we try to open twice the same file from the same branch, we get
  -- vim failures "buffer name already in use"
  if not pcall(vim.api.nvim_exec2, base_bufcmd, { output = false }) then
    local succeeded = false
    local fname_without_ext = fname_without_path:match("(.*)%.[^.]+$")
    local fname_ext = fname_without_path:match(".*(%.[^.]+)$")
    local i = 2
    while not succeeded and i < 20 do
      succeeded = pcall(
        vim.api.nvim_exec2,
        "silent file [" .. branch .. "] " .. fname_without_ext .. " (" .. i .. ")" .. fname_ext,
        { output = false }
      )
      i = i + 1
    end
  end
  vim.api.nvim_command("filetype detect")
  vim.api.nvim_command("setlocal readonly")
  vim.bo.readonly = true
  vim.bo.modified = false
  vim.bo.modifiable = false
end

-- function taken from gitsigns
local function parse_fugitive_uri(name)
  local _, _, root_path, sub_module_path, commit, real_path = name:find([[^fugitive://(.*)/%.git(.*/)/(%x-)/(.*)]])
  if commit == "0" then
    commit = nil
  end
  if root_path then
    sub_module_path = sub_module_path:gsub("^/modules", "")
    name = root_path .. sub_module_path .. real_path
    return name, commit
  end
  return nil, nil
end

-- function taken from gitsigns
local function parse_gitsigns_uri(name)
  local _, _, root_path, commit, rel_path = name:find([[^gitsigns://(.*)/%.git/(.*):(.*)]])
  if commit == ":0" then
    commit = nil
  end
  if root_path then
    name = root_path .. "/" .. rel_path
    return name, commit
  end
  return nil, nil
end

local function fname_commit_associated_with_buffer()
  if vim.b.agitator_path_in_git_prj ~= nil then
    return vim.b.agitator_path_in_git_prj, vim.b.agitator_commit
  end
  local bufnr = vim.fn.bufnr("%")
  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  local f, c = parse_fugitive_uri(buf_name)
  if f ~= nil then
    return f, c
  end
  f, c = parse_gitsigns_uri(buf_name)
  if f ~= nil then
    return f, c
  end
  return nil, nil
end

local function get_relative_fname()
  -- need fs_realpath to resolve symbolic links for instance
  local fname = vim.loop.fs_realpath(vim.api.nvim_buf_get_name(0))
    or vim.api.nvim_buf_call(0, function()
      return vim.fn.expand("%:p")
    end)
  return fname:gsub(escape_pattern(get_cwd()) .. "/", "")
end

return {
  open_file_branch = open_file_branch,
  get_relative_fname = get_relative_fname,
  escape_pattern = escape_pattern,
  git_root_folder = git_root_folder,
  fname_commit_associated_with_buffer = fname_commit_associated_with_buffer,
  get_cwd = get_cwd,
}
