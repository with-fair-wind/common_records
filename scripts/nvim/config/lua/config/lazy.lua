local plugin_root = vim.fn.stdpath("data") .. "/lazy"
local manager = plugin_root .. "/lazy.nvim"
if not vim.uv.fs_stat(manager) then
  local result = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", manager,
  })
  if vim.v.shell_error ~= 0 then
    error("Cannot bootstrap lazy.nvim. Check Git/network/proxy:\n" .. result)
  end
end
vim.opt.runtimepath:prepend(manager)
local specs = {
  { "LazyVim/LazyVim", import = "lazyvim.plugins" },
  { import = "lazyvim.plugins.extras.lang.clangd" },
  { import = "lazyvim.plugins.extras.lang.cmake" },
  { import = "lazyvim.plugins.extras.dap.core" },
  { import = "plugins" },
}
require("lazy").setup(specs, {
  root = plugin_root,
  lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
  defaults = { lazy = false, version = false },
  checker = { enabled = false },
  change_detection = { notify = false },
})
