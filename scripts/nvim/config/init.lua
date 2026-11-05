-- Capture system LLVM paths before Mason adjusts PATH.
local override_path = vim.fn.stdpath("config") .. "/lua/config/local.lua"
local local_config = vim.uv.fs_stat(override_path) and dofile(override_path) or {}
assert(type(local_config) == "table", "config/local.lua must return a table")
vim.g.nvim_cpp_tools = {
  clangd = local_config.clangd or vim.fn.exepath("clangd"),
  clang_format = local_config.clang_format or vim.fn.exepath("clang-format"),
  clang_tidy = local_config.clang_tidy == true,
  clangd_args = local_config.clangd_args or {},
}
require("config.lazy")
