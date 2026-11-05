local tools = vim.g.nvim_cpp_tools
local clangd_command = {
  tools.clangd ~= "" and tools.clangd or "clangd",
  "--background-index",
  "--completion-style=detailed",
  tools.clang_tidy and "--clang-tidy" or "--clang-tidy=false",
}
vim.list_extend(clangd_command, tools.clangd_args)

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          mason = false,
          cmd = clangd_command,
          root_markers = { "compile_commands.json", ".clangd", "CMakeLists.txt", ".git" },
        },
      },
    },
  },
  { "mason-org/mason.nvim", opts = { PATH = "append" } },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = { c = { "clang_format" }, cpp = { "clang_format" } },
      formatters = {
        clang_format = { command = tools.clang_format ~= "" and tools.clang_format or "clang-format" },
      },
    },
  },
  {
    "Civitasv/cmake-tools.nvim",
    cmd = {
      "CMakeSelectConfigurePreset", "CMakeSelectBuildPreset", "CMakeSelectBuildTarget",
      "CMakeGenerate", "CMakeBuild", "CMakeRun", "CMakeDebug", "CMakeRunTest",
      "CMakeSelectLaunchTarget", "CMakeQuickBuild",
    },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>mg", "<cmd>CMakeGenerate<cr>", desc = "CMake configure" },
      { "<leader>mb", "<cmd>CMakeBuild<cr>", desc = "CMake build" },
      { "<leader>mp", "<cmd>CMakeSelectConfigurePreset<cr>", desc = "CMake configure preset" },
      { "<leader>mt", "<cmd>CMakeSelectBuildTarget<cr>", desc = "CMake build target" },
      { "<leader>mr", "<cmd>CMakeRun<cr>", desc = "CMake run" },
      { "<leader>md", "<cmd>CMakeDebug<cr>", desc = "CMake debug" },
      { "<leader>ms", "<cmd>CMakeRunTest<cr>", desc = "CMake tests" },
    },
    opts = {
      cmake_use_preset = true,
      cmake_regenerate_on_save = false,
      cmake_generate_options = { "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" },
      cmake_compile_commands_options = { action = "copy", target = function() return vim.fn.getcwd() end },
      cmake_executor = { name = "quickfix" },
      cmake_runner = { name = "terminal" },
    },
  },
}
