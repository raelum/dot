-- Neovim configuration

-- Leader key (Space)
vim.g.mapleader = " "

-- Clipboard synchronization with Android system clipboard via Termux:API
vim.opt.clipboard = "unnamedplus"

-- Mouse and trackpad scrolling support
vim.opt.mouse = "a"

-- UI & Editor feel
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.scrolloff = 4
vim.opt.wrap = true
vim.opt.breakindent = true
vim.opt.showbreak = "↳ "

-- VS Code-style git diff bars after line numbers
function _G.custom_statuscolumn()
  return vim.wo.number and "%=%l %#LineNr#%s" or "%s"
end
vim.opt.statuscolumn = "%!v:lua.custom_statuscolumn()"

-- Indentation defaults
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Key mapping & response feel (Tmux-style: wait indefinitely on key sequences)
vim.opt.updatetime = 250
vim.opt.timeout = false
vim.opt.showcmd = true

-- =============================================================================
-- Auto-reload Files Changed Outside Neovim (VS Code-style autoread)
-- =============================================================================
vim.opt.autoread = true

local autoread_group = vim.api.nvim_create_augroup("AutoReadGroup", { clear = true })

-- Check for external modifications on focus, buffer switch, or cursor pause
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  group = autoread_group,
  pattern = "*",
  callback = function()
    if vim.fn.mode() ~= "c" and vim.fn.getcmdwintype() == "" then
      vim.cmd("checktime")
    end
  end,
})

-- Reload silently without the "Press Enter" prompt (prompts only on conflict)
vim.api.nvim_create_autocmd("FileChangedShell", {
  group = autoread_group,
  pattern = "*",
  callback = function()
    vim.v.fcs_choice = (vim.v.fcs_reason ~= "conflict") and "reload" or "ask"
  end,
})

-- Keep diff signs synchronized when files reload or when returning to Neovim
vim.api.nvim_create_autocmd({ "FocusGained", "FileChangedShellPost" }, {
  group = autoread_group,
  pattern = "*",
  callback = function()
    vim.schedule(function()
      if _G.refresh_all_jj_diffs then _G.refresh_all_jj_diffs() end
    end)
  end,
})

-- =============================================================================
-- Bootstrap Plugin Manager (lazy.nvim)
-- =============================================================================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

if not _G._lazy_did_setup then
  require("lazy").setup({
    spec = {
      { "echasnovski/mini.diff", version = false },
    },
    install = { colorscheme = { "habamax" } },
    checker = { enabled = false }, -- Avoid background git polls on mobile battery
  })
  _G._lazy_did_setup = true
end

-- =============================================================================
-- Jujutsu Tools & Git Diff Integration (mini.diff)
-- =============================================================================
local jj = require("jj")
jj.setup()

local has_minidiff, minidiff = pcall(require, "mini.diff")
if has_minidiff then
  minidiff.setup({
    source = { jj.source, minidiff.gen_source.git() },
    view = {
      style = "sign",
      signs = {
        add    = "│",
        change = "│",
        delete = "_",
      },
    },
    options = {
      linematch = 60, -- Enhanced word-level intra-line alignment
    },
    mappings = {
      apply = "",
      reset = "",
      textobject = "",
      goto_first = "",
      goto_prev = "",
      goto_next = "",
      goto_last = "",
    },
  })

  -- VS Code-style Diff Colors for Gutter Signs
  vim.api.nvim_set_hl(0, "MiniDiffSignAdd",       { fg = "#2ea043", bold = true }) -- Green (Added)
  vim.api.nvim_set_hl(0, "MiniDiffSignChange",    { fg = "#007acc", bold = true }) -- Blue (Modified)
  vim.api.nvim_set_hl(0, "MiniDiffSignDelete",    { fg = "#f85149", bold = true }) -- Red (Deleted)

  -- VS Code-style Inline Overlay Colors (with Word-level Diff Highlighting)
  -- 1. Reference lines (old / deleted version from base commit):
  vim.api.nvim_set_hl(0, "MiniDiffOverContext",    { bg = "#2d1619", fg = "#8b949e", italic = true })              -- Unchanged text in old line
  vim.api.nvim_set_hl(0, "MiniDiffOverChange",     { bg = "#5c1d24", fg = "#ff7b72", bold = true, strikethrough = true }) -- Removed words in old line
  vim.api.nvim_set_hl(0, "MiniDiffOverDelete",     { bg = "#3b1a1e", fg = "#ff7b72", italic = true })              -- Fully deleted old lines

  -- 2. Buffer lines (new / working copy version):
  vim.api.nvim_set_hl(0, "MiniDiffOverContextBuf", { bg = "#14251a" })                                             -- Modified line background
  vim.api.nvim_set_hl(0, "MiniDiffOverChangeBuf",  { bg = "#1f5436", fg = "#56d364", bold = true })               -- Added / changed words
  vim.api.nvim_set_hl(0, "MiniDiffOverAdd",        { bg = "#1b382b" })                                             -- Fully added new lines

  -- Toggle inline diff overlay (VS Code-style with word-level highlights)
  local function toggle_inline_diff()
    minidiff.toggle_overlay(0)
  end

  vim.keymap.set("n", "<leader>jd", toggle_inline_diff, { desc = "Toggle inline diff overlay" })

  -- Jump between diff changes
  vim.keymap.set("n", "<leader>jn", function() minidiff.goto_hunk("next") end, { desc = "Next diff change" })
  vim.keymap.set("n", "<leader>jp", function() minidiff.goto_hunk("prev") end, { desc = "Previous diff change" })
end

-- =============================================================================
-- Quick Save & Quit Shortcuts (<leader>w, <leader>q, <leader>Q)
-- =============================================================================
vim.keymap.set("n", "<leader>w", "<cmd>write<CR>", { desc = "Save current file" })
vim.keymap.set("n", "<leader>q", "<cmd>x<CR>", { desc = "Save and quit current buffer" })
vim.keymap.set("n", "<leader>Q", "<cmd>q!<CR>", { desc = "Quit without saving" })

-- =============================================================================
-- Quick Escape (kk with timeout)
-- =============================================================================
local last_k_time = 0
local quick_escape_timeout_ms = 300

-- Escape to Normal mode on double-tap 'k' within timeout
vim.keymap.set("i", "k", function()
  local now = (vim.uv or vim.loop).now()
  local col = vim.fn.col(".")
  local prev_char = col > 1 and vim.fn.getline("."):sub(col - 1, col - 1) or ""

  if (now - last_k_time) <= quick_escape_timeout_ms and prev_char == "k" then
    last_k_time = 0
    return "<BS><Esc>" -- Delete previous 'k' and exit to Normal mode
  end

  last_k_time = now
  return "k"
end, { expr = true, desc = "Escape to Normal mode on fast kk" })

-- =============================================================================
-- Generic Configuration Reload Shortcut (<leader>r)
-- =============================================================================
local function reload_config()
  if vim.loader and vim.loader.reset then vim.loader.reset() end

  -- Automatically unload all custom modules in ~/.config/nvim/lua/
  local lua_dir = vim.fn.stdpath("config") .. "/lua"
  for _, file in ipairs(vim.fn.globpath(lua_dir, "**/*.lua", false, true)) do
    local mod = file:sub(#lua_dir + 2):gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")
    package.loaded[mod] = nil
  end

  local config = (vim.env.MYVIMRC and vim.env.MYVIMRC ~= "" and vim.env.MYVIMRC) or (vim.fn.stdpath("config") .. "/init.lua")
  local ok, err = pcall(vim.cmd.source, config)
  vim.notify(ok and "✓ Config reloaded" or ("Error reloading: " .. tostring(err)), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
end

vim.api.nvim_create_user_command("ReloadConfig", reload_config, { desc = "Reload Neovim configuration" })
vim.keymap.set("n", "<leader>r", reload_config, { desc = "Reload Neovim configuration" })

-- =============================================================================
-- Send Code to Antigravity CLI (<leader>a)
-- Yanks selection (or current line), sends to agy pane in Tmux with bracketed paste,
-- inserts two newlines (Ctrl+J), and switches focus directly to the agy prompt.
-- Auto-closes the popup if triggered from the floating todo popup.
-- =============================================================================
local function send_to_agy(text)
  if not text or vim.trim(text) == "" then return end

  -- Send text with bracketed paste, submit prompt, and switch focus to agy
  vim.system({
    "tmux",
    "copy-mode", "-q", "-t", ":agy",
    ";", "load-buffer", "-b", "agy_input", "-",
    ";", "paste-buffer", "-p", "-t", ":agy", "-b", "agy_input",
    ";", "send-keys", "-t", ":agy", "C-j", "C-j",
    ";", "select-window", "-t", ":agy",
    ";", "select-pane", "-t", ":agy",
  }, { stdin = text }):wait()

  -- Auto-close popup if running inside the floating todo popup
  if vim.env.TODO_POPUP == "1" then
    vim.schedule(function()
      vim.cmd("wq")
    end)
  end
end

vim.keymap.set("n", "<leader>a", function()
  send_to_agy(vim.api.nvim_get_current_line())
end, { desc = "Send current line to agy" })

vim.keymap.set("x", "<leader>a", function()
  vim.cmd('normal! "zy')
  send_to_agy(vim.fn.getreg("z"))
end, { desc = "Send visual selection to agy" })

-- Save and quit todo popup with 'q' in normal mode
if vim.env.TODO_POPUP == "1" then
  vim.keymap.set("n", "q", "<cmd>wq<CR>", { silent = true, desc = "Save and quit todo popup" })
end


