-- Copy to local.lua in the DEPLOYED configuration, not the shared repository.
-- Use forward slashes for Windows paths. Omit paths to use system PATH.
return {
  -- clangd = "D:/tools/llvm/bin/clangd.exe",
  -- clang_format = "D:/tools/llvm/bin/clang-format.exe",
  clang_tidy = false, -- Enable after clangd parses the project correctly.
  clangd_args = {}, -- e.g. { "-j=4" }; avoid global project-specific database paths.
}
