-- =============================================================================
-- Project Switcher (Auto-save, Open First Modified Diff, or Fallback File)
-- =============================================================================

local M = {}

-- Jump to first diff hunk in buf_id (waiting for MiniDiffUpdated if still computing)
local function jump_to_first_diff(buf_id)
  local has_diff, diff = pcall(require, "mini.diff")
  if not has_diff then return end

  local function do_jump()
    pcall(diff.goto_hunk, "first")
    vim.cmd("normal! zz")
  end

  local data = diff.get_buf_data(buf_id)
  if data and data.hunks and #data.hunks > 0 then
    do_jump()
  else
    vim.api.nvim_create_autocmd("User", {
      pattern = "MiniDiffUpdated",
      once = true,
      callback = function(ev)
        if ev.buf == buf_id then do_jump() end
      end,
    })
  end
end

-- Switch Neovim to target project directory
function M.open_project(dir)
  if not dir or dir == "" then return end
  local target = vim.fs.normalize(vim.fn.fnamemodify(dir, ":p"))
  if vim.fn.isdirectory(target) == 0 then
    return vim.notify("Directory not found: " .. target, vim.log.levels.ERROR)
  end

  -- Auto-save modified buffers with confirmation prompt fallback
  if not pcall(vim.cmd, "confirm wall") then
    return vim.notify("Project switch cancelled", vim.log.levels.WARN)
  end

  vim.cmd("silent! %bd!")
  vim.api.nvim_set_current_dir(target)

  local ok_jj, jj = pcall(require, "jj")
  local first_file = ok_jj and jj.get_first_modified_file(target) or nil
  if first_file then
    vim.cmd.edit(first_file)
    jump_to_first_diff(vim.api.nvim_get_current_buf())
    return
  end

  -- Clean repo or non-JJ directory: open README or directory root
  local readme = target .. "/README.md"
  vim.cmd.edit(vim.fn.filereadable(readme) == 1 and readme or target)
  if ok_jj then vim.schedule(jj.refresh_all_diffs) end
end

-- Interactive fuzzy project selector via mini.pick
function M.select_project()
  local code_dir = vim.fs.normalize(vim.fn.expand("~/code"))
  local projects = {}
  local handle = vim.uv.fs_scandir(code_dir)
  if handle then
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then break end
      if typ == "directory" and not name:match("^%.") then
        table.insert(projects, name)
      end
    end
  end
  table.sort(projects)

  if #projects == 0 then
    return vim.notify("No projects found in ~/code", vim.log.levels.WARN)
  end

  local ok_pick, pick = pcall(require, "mini.pick")
  if not ok_pick then
    return vim.notify("mini.pick is not installed", vim.log.levels.ERROR)
  end

  pick.start({
    source = {
      name = "Projects",
      items = projects,
      choose = function(item)
        if item then
          vim.schedule(function()
            M.open_project(code_dir .. "/" .. item)
          end)
        end
      end,
    },
  })
end

function M.setup()
  vim.api.nvim_create_user_command("ProjectOpen", function(opts)
    if opts.args and vim.trim(opts.args) ~= "" then
      M.open_project(opts.args)
    else
      M.select_project()
    end
  end, { nargs = "?", complete = "dir", desc = "Switch project in Neovim" })

  vim.keymap.set("n", "<leader>p", M.select_project, { desc = "Select project" })
end

return M
