-- =============================================================================
-- Jujutsu (jj) Tools: Interactive Modified Files Menu & Diff Adapter
-- =============================================================================

local M = {}

-- Diff mode: false = working copy only (@-), true = include staged commit (@--)
M.include_staged = false

-- =============================================================================
-- Shared Helpers
-- =============================================================================

-- Execute a jj command and return stdout lines, or nil on failure
local function run_jj(args, notify_err)
  local cmd = { "jj", "--no-pager", "--color=never" }
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 then
    if notify_err and res.stderr and vim.trim(res.stderr) ~= "" then
      vim.notify("JJ error: " .. vim.trim(res.stderr), vim.log.levels.ERROR)
    end
    return nil
  end
  return vim.split(res.stdout or "", "\n", { trimempty = true })
end

-- Check if a mutable staged commit (@-) exists
function M.has_staged_commit()
  local res = run_jj({ "log", "-r", "@- & mutable()", "-T", "change_id", "--no-graph" })
  return res and res[1] and vim.trim(res[1]) ~= ""
end

-- Prompt user for single-key (y/n) confirmation on the command line
local function confirm_yn(prompt)
  vim.cmd("redraw")
  vim.api.nvim_echo({ { prompt .. " (y/n) ", "Question" } }, false, {})
  local char = vim.fn.getcharstr()
  vim.cmd("redraw")
  return char == "y" or char == "Y"
end

-- =============================================================================
-- Jujutsu Diff Reference Adapter (for mini.diff)
-- =============================================================================

-- Retrieve baseline file content from `jj file show -r <base>` for mini.diff
function M.get_ref_text(buf_id)
  local path = vim.api.nvim_buf_get_name(buf_id)
  if path == "" or vim.bo[buf_id].buftype ~= "" then return nil end
  local repo_root = vim.fs.root(path, ".jj")
  if not repo_root then return nil end
  local norm_path = vim.fs.normalize(path)
  if not vim.startswith(norm_path, repo_root .. "/") then return nil end
  local rel_path = norm_path:sub(#repo_root + 2)

  local base = (M.include_staged and M.has_staged_commit()) and "@--" or "@-"
  local res = vim.system({ "jj", "--no-pager", "--color=never", "file", "show", "-r", base, rel_path }, { text = true }):wait()
  return res.code == 0 and (res.stdout or "") or ""
end

-- Refresh gutter diff signs across all active buffers
function M.refresh_all_diffs()
  local has_diff, diff = pcall(require, "mini.diff")
  if not has_diff then return end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) ~= "" then
      local text = M.get_ref_text(b)
      if text ~= nil then
        pcall(diff.set_ref_text, b, text)
      end
    end
  end
end
_G.refresh_all_jj_diffs = M.refresh_all_diffs

-- Toggle diff mode between working copy only and including staged commit
function M.toggle_diff_base()
  M.include_staged = not M.include_staged

  local msg
  if M.include_staged then
    if M.has_staged_commit() then
      msg = "Diff mode: includes staged changes"
    else
      msg = "Diff mode: includes staged changes (none currently staged)"
    end
  else
    msg = "Diff mode: working copy only"
  end

  M.refresh_all_diffs()
  vim.cmd("redraw")
  vim.api.nvim_echo({ { msg, "Directory" } }, false, {})
end

-- Custom provider passed into mini.diff setup
M.source = {
  name = "jj",
  attach = function(buf_id)
    local text = M.get_ref_text(buf_id)
    if text ~= nil then
      local has_diff, diff = pcall(require, "mini.diff")
      if has_diff then diff.set_ref_text(buf_id, text) end
      return true
    end
    return false
  end,
}

-- =============================================================================
-- Jujutsu Modified Files Menu (Browse, Stage & Unstage, Fig-style)
-- =============================================================================

-- Muted & italic highlight group for commit message in menu
vim.api.nvim_set_hl(0, "JJCommitMsg", { link = "Comment", italic = true, default = true })

-- Interactive dashboard to review working copy and stage into commit (@-)
local function open_jj_files_menu()
  local win, buf = nil, nil

  -- Capture active buffer's normalized file path to auto-focus on initial open
  local initial_buf = vim.api.nvim_get_current_buf()
  local initial_path = vim.api.nvim_buf_get_name(initial_buf)
  local active_file = (initial_path and initial_path ~= "") and vim.fs.normalize(initial_path) or nil

  -- Ensure current buffer is within a Jujutsu repository
  local repo_root = vim.fs.root(0, ".jj") or vim.fs.root(vim.fn.getcwd(), ".jj")
  if not repo_root then return vim.notify("Not inside a Jujutsu repository", vim.log.levels.WARN) end

  -- Get first-line description of staged commit (@-)
  local function get_staged_desc()
    local res = run_jj({ "log", "-r", "@-", "-T", "description.first_line()", "--no-graph" })
    return (res and res[1] and vim.trim(res[1]) ~= "") and vim.trim(res[1]) or nil
  end

  local line_to_entry = {}

  -- Parse `jj diff --summary` output into structured file entries with status
  local function parse_entries(raw_lines, section)
    local entries = {}
    for _, line in ipairs(raw_lines or {}) do
      local status = line:sub(1, 1)
      local path_part = vim.trim(line:sub(3))
      local old_path, new_path = nil, path_part
      -- Handle renames ('R'): compact 'prefix/{old => new}/suffix' or full 'old => new'
      if status == "R" then
        local prefix, old_sub, new_sub, suffix = path_part:match("^(.-)%{(.-)%s*=>%s*(.-)%}(.*)$")
        if prefix then
          old_path = prefix .. old_sub .. suffix
          new_path = prefix .. new_sub .. suffix
        else
          local old_p, new_p = path_part:match("^(.-)%s*=>%s*(.-)$")
          if old_p then
            old_path = old_p
            new_path = new_p
          end
        end
      end

      -- Renames require both old and new paths so JJ can stage/restore them atomically
      local vcs_paths = { new_path }
      if old_path and old_path ~= new_path then
        vcs_paths = { old_path, new_path }
      end

      table.insert(entries, {
        section = section,
        status = status,
        display_path = path_part,
        edit_path = repo_root .. "/" .. new_path,
        vcs_paths = vcs_paths,
      })
    end
    return entries
  end

  -- Build buffer lines, apply syntax highlights, and position floating window
  local function render(target_row)
    local working_entries = parse_entries(run_jj({ "diff", "-r", "@-..@", "--summary" }), "working")
    local staged_entries = {}
    local has_staged = M.has_staged_commit()
    if has_staged then
      staged_entries = parse_entries(run_jj({ "diff", "-r", "@--..@-", "--summary" }), "staged")
    end

    local buf_lines = {}
    line_to_entry = {}
    local highlights = {}
    local first_file_line = nil

    -- Format a section header and file list with sign highlights
    local function add_section(title, entries, empty_msg, subtitle)
      table.insert(buf_lines, " " .. title)
      table.insert(highlights, { #buf_lines - 1, 0, -1, "Title" })
      if subtitle and subtitle ~= "" then
        table.insert(buf_lines, '   "' .. subtitle .. '"')
        table.insert(highlights, { #buf_lines - 1, 0, -1, "JJCommitMsg" })
      end
      if #entries == 0 then
        table.insert(buf_lines, "   " .. empty_msg)
        table.insert(highlights, { #buf_lines - 1, 0, -1, "Comment" })
      else
        for _, item in ipairs(entries) do
          table.insert(buf_lines, string.format("   %s  %s", item.status, item.display_path))
          line_to_entry[#buf_lines] = item
          if not first_file_line then first_file_line = #buf_lines end
          local hl = (item.status == "A" and "MiniDiffSignAdd")
            or (item.status == "M" and "MiniDiffSignChange")
            or (item.status == "D" and "MiniDiffSignDelete")
            or (item.status == "R" and "MiniDiffSignChange") or "DiagnosticWarn"
          table.insert(highlights, { #buf_lines - 1, 3, 4, hl })
        end
      end
    end

    add_section("Working Copy", working_entries, "(clean)")
    table.insert(buf_lines, "")

    if has_staged then
      local desc = get_staged_desc()
      add_section("Staged Commit", staged_entries, "(empty)", desc)
    else
      add_section("Staged Commit", {}, "(none)")
    end

    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = "nofile"
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, buf_lines)
    vim.bo[buf].modifiable = false

    local ns = vim.api.nvim_create_namespace("jj_files_menu")
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(buf, ns, h[4], h[1], h[2], h[3])
    end

    -- Window configuration: centered with fixed maximum width
    local width = math.min(80, vim.o.columns - 4)
    local height = math.min(math.floor(vim.o.lines * 0.8), #buf_lines)
    local win_opts = {
      relative = "editor",
      width = width,
      height = height,
      row = math.max(1, math.floor((vim.o.lines - height) / 2)),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      style = "minimal",
      border = "rounded",
      title = " JJ Status ",
      title_pos = "center",
      footer = " [a] Stage  [u] Unstage  [x] Discard  [m] Msg   [p] Push ",
      footer_pos = "center",
    }

    if not win or not vim.api.nvim_win_is_valid(win) then
      win = vim.api.nvim_open_win(buf, true, win_opts)
    else
      vim.api.nvim_win_set_config(win, win_opts)
    end

    -- Set cursor to target row (or first file entry if none specified)
    local cursor_row = math.max(1, math.min(target_row or first_file_line or 2, #buf_lines))
    pcall(vim.api.nvim_win_set_cursor, win, { cursor_row, 5 })
  end

  -- Find line number for a given absolute file path (scans top-to-bottom: working copy first)
  local function find_file_row(file_path)
    if not file_path or file_path == "" or not buf then return nil end
    local norm = vim.fs.normalize(file_path)
    for line_num = 1, vim.api.nvim_buf_line_count(buf) do
      local item = line_to_entry[line_num]
      if item and item.edit_path and vim.fs.normalize(item.edit_path) == norm then
        return line_num
      end
    end
    return nil
  end

  -- Safely close the floating menu window
  local function close_win()
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- Open currently selected file in standard editor buffer
  local function open_entry()
    local cur_row = vim.api.nvim_win_get_cursor(win)[1]
    local entry = line_to_entry[cur_row]
    if not entry or (entry.status == "D" and vim.fn.filereadable(entry.edit_path) == 0) then return end
    close_win()
    vim.cmd.edit(entry.edit_path)
  end

  -- Squash working copy file into staged commit (@-), prompting if initial commit
  local function stage_entry()
    local cur_row = vim.api.nvim_win_get_cursor(win)[1]
    local entry = line_to_entry[cur_row]
    if not entry or entry.section == "staged" then return end

    if M.has_staged_commit() then
      local args = { "squash" }
      vim.list_extend(args, entry.vcs_paths)
      if run_jj(args, true) then
        M.refresh_all_diffs()
        render(cur_row)
      end
    else
      vim.ui.input({ prompt = "Commit message: " }, function(input)
        vim.cmd("redraw") -- Clear input prompt from cmdline to prevent "Press ENTER" prompt
        if not input or vim.trim(input) == "" then return end
        local args = { "commit", "-m", vim.trim(input) }
        vim.list_extend(args, entry.vcs_paths)
        if run_jj(args, true) then
          M.refresh_all_diffs()
          render(cur_row)
        end
      end)
    end
  end

  -- Move file from staged commit (@-) back into working copy (@)
  local function unstage_entry()
    local cur_row = vim.api.nvim_win_get_cursor(win)[1]
    local entry = line_to_entry[cur_row]
    if not entry or entry.section ~= "staged" then return end
    if not M.has_staged_commit() then
      return vim.notify("No staged commit to unstage from", vim.log.levels.WARN)
    end

    local args = { "squash", "--from", "@-", "--into", "@", "--keep-emptied" }
    vim.list_extend(args, entry.vcs_paths)
    if run_jj(args, true) then
      M.refresh_all_diffs()
      render(cur_row)
    end
  end

  -- Discard uncommitted changes to file via `jj restore` after confirmation
  local function discard_entry()
    local cur_row = vim.api.nvim_win_get_cursor(win)[1]
    local entry = line_to_entry[cur_row]
    if not entry or entry.section ~= "working" then return end

    if confirm_yn("Discard changes to '" .. entry.display_path .. "'?") then
      local args = { "restore" }
      vim.list_extend(args, entry.vcs_paths)
      if run_jj(args, true) then
        vim.cmd.checktime()
        M.refresh_all_diffs()
        render(cur_row)
      end
    end
  end

  -- Edit commit description for staged commit (@-)
  local function describe_staged()
    if not M.has_staged_commit() then
      return vim.notify("No staged commit to describe", vim.log.levels.WARN)
    end
    local cur_row = (win and vim.api.nvim_win_is_valid(win)) and vim.api.nvim_win_get_cursor(win)[1] or nil
    vim.ui.input({ prompt = "Edit commit message: ", default = get_staged_desc() or "" }, function(input)
      vim.cmd("redraw") -- Clear input prompt from cmdline to prevent "Press ENTER" prompt
      if input and vim.trim(input) ~= "" and run_jj({ "describe", "-r", "@-", "-m", vim.trim(input) }, true) then
        render(cur_row)
      end
    end)
  end

  -- Push staged commit (@-) to remote Git repository
  local function push_staged()
    if not M.has_staged_commit() then
      return vim.notify("No staged commit to push", vim.log.levels.WARN)
    end

    local is_empty = run_jj({ "log", "-r", "@- & empty()", "-T", "change_id", "--no-graph" })
    if is_empty and is_empty[1] and vim.trim(is_empty[1]) ~= "" then
      return vim.notify("Staged commit has no file changes to push", vim.log.levels.WARN)
    end

    if not confirm_yn("Push staged commit to remote?") then
      return
    end

    -- Advance closest tracking bookmark (defaulting to main) to @-
    local bm_res = run_jj({ "log", "-r", "heads(::@- & bookmarks())", "-T", "bookmarks", "--no-graph" })
    local bm_raw = (bm_res and bm_res[1] and vim.trim(bm_res[1]) ~= "") and vim.trim(bm_res[1]) or "main"
    local bookmark_name = vim.split(bm_raw, "%s+")[1]
    run_jj({ "bookmark", "set", bookmark_name, "-r", "@-" }, true)

    vim.notify("Pushing to remote...", vim.log.levels.INFO)
    local res = run_jj({ "git", "push" }, true)
    if res then
      vim.notify("✓ Successfully pushed to remote!", vim.log.levels.INFO)
      M.refresh_all_diffs()
      close_win()
    end
  end

  render()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  -- On initial menu open, focus the active buffer's file if it has changes
  if active_file then
    local initial_row = find_file_row(active_file)
    if initial_row then
      pcall(vim.api.nvim_win_set_cursor, win, { initial_row, 5 })
    end
  end

  -- Auto-refresh status menu when switching back to Neovim
  vim.api.nvim_create_autocmd("FocusGained", {
    buffer = buf,
    callback = function()
      if win and vim.api.nvim_win_is_valid(win) then
        local cur_row = vim.api.nvim_win_get_cursor(win)[1]
        render(cur_row)
      end
    end,
  })

  -- Keybindings for the menu
  vim.keymap.set("n", "<CR>",  open_entry,       { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "a",     stage_entry,      { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "u",     unstage_entry,    { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "x",     discard_entry,    { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "m",     describe_staged,  { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "p",     push_staged,      { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "q",     close_win,        { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close_win,        { buffer = buf, nowait = true, silent = true })
end

M.open_files_menu = open_jj_files_menu

-- =============================================================================
-- Setup & Keybindings
-- =============================================================================

-- Soft-wrap Virtual Lines in Diff Overlay (neovim#18282)
local function wrap_virt_line(line, max_w)
  local wrapped, current, width = {}, {}, 0

  for chunk_idx, chunk in ipairs(line) do
    local text, hl = chunk[1], chunk[2]
    -- Skip mini.diff's trailing full-width padding chunk
    if chunk_idx == #line and text:match("^ +$") then
      break
    end

    -- Create virtual lines one chunk at a time, wrapping if necessary
    while #text > 0 do
      if width >= max_w then
        table.insert(wrapped, current)
        current = { { "↳ ", "NonText" } }
        width = 2
      end

      local avail = max_w - width
      local part = text:sub(1, avail)
      table.insert(current, { part, hl })
      width = width + #part
      text = text:sub(avail + 1)
    end
  end

  if #current > 0 then table.insert(wrapped, current) end
  return #wrapped > 0 and wrapped or { line }
end

-- Intercept mini.diff overlay extmarks to soft-wrap virtual lines to window width
function M.setup_diff_wrap()
  if _G._minidiff_virt_lines_wrapped then return end -- Avoid re-wrapping on config reload
  local overlay_ns = vim.api.nvim_create_namespace("MiniDiffOverlay")
  local orig_set_extmark = vim.api.nvim_buf_set_extmark

  vim.api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
    -- Only intercept virtual lines placed by mini.diff
    if ns == overlay_ns and opts and opts.virt_lines and #opts.virt_lines > 0 then
      -- Calculate usable text width (window width minus gutter)
      local win = vim.fn.bufwinid(buf)
      if win == -1 then win = vim.api.nvim_get_current_win() end
      local win_info = vim.fn.getwininfo(win)
      local textoff = (win_info and win_info[1]) and win_info[1].textoff or 4
      local max_w = math.max(20, vim.api.nvim_win_get_width(win) - textoff)

      local new_virt_lines = {}
      for _, line in ipairs(opts.virt_lines) do
        for _, wline in ipairs(wrap_virt_line(line, max_w)) do
          table.insert(new_virt_lines, wline)
        end
      end
      opts.virt_lines = new_virt_lines
    end
    return orig_set_extmark(buf, ns, row, col, opts)
  end

  _G._minidiff_virt_lines_wrapped = true
end

function M.setup()
  M.setup_diff_wrap()
  vim.api.nvim_create_user_command("JJStatus", function()
    M.open_files_menu()
  end, { desc = "Open Jujutsu status menu (working copy & staged commit)" })

  vim.keymap.set("n", "<leader>jj", M.open_files_menu, { desc = "JJ Status" })
  vim.keymap.set("n", "<leader>jt", M.toggle_diff_base, { desc = "Toggle diff mode (working vs staged)" })
end

return M
