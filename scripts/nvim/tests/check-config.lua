-- Run with: nvim --headless -u NONE -l scripts/nvim/tests/check-config.lua
-- Check the Lua configuration with fake plugin modules; no plugin downloads.
local root = "scripts/nvim/config"
for _, file in ipairs(vim.fn.glob(root .. "/**/*.lua", false, true)) do
  assert(loadfile(file), "Invalid Lua: " .. file)
end
local previous = vim.env.XDG_CONFIG_HOME
vim.env.XDG_CONFIG_HOME = vim.fn.getcwd() .. "/scripts/nvim/tests/.work/config-syntax"
package.loaded["config.lazy"] = true
local original_exepath = vim.fn.exepath
vim.fn.exepath = function(tool) return "C:/LLVM/bin/" .. tool .. ".exe" end
dofile(root .. "/init.lua")
vim.fn.exepath = original_exepath
local specs = dofile(root .. "/lua/plugins/cpp.lua")
assert(specs[1].opts.servers.clangd.mason == false)
assert(specs[1].opts.servers.clangd.cmd[1] == "C:/LLVM/bin/clangd.exe")
assert(vim.tbl_contains(specs[1].opts.servers.clangd.cmd, "--clang-tidy=false"))
assert(specs[3].opts.formatters.clang_format.command == "C:/LLVM/bin/clang-format.exe")
assert(specs[4].opts.cmake_compile_commands_options.action == "copy")
local captured
package.loaded["lazy"] = { setup = function(plugin_specs, opts) captured = { plugin_specs, opts } end }
local stat = vim.uv.fs_stat
vim.uv.fs_stat = function() return {} end
dofile(root .. "/lua/config/lazy.lua")
vim.uv.fs_stat = stat
vim.env.XDG_CONFIG_HOME = previous
assert(#captured[1] == 5)
assert(captured[2].checker.enabled == false)
print("Lua syntax and tool-provider configuration checks passed.")
