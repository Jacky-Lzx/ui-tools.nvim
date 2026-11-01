-- Point dir at your local checkout. Disable Snacks indent/statuscolumn, remove
-- its Zen/Zoom/dim mappings, and disable nvim-scrollbar before using this spec.
return {
  dir = vim.fn.expand("~/Documents/Github/nvim_plugins/ui-tools.nvim"),
  name = "ui-tools.nvim",
  main = "ui_tools",
  lazy = false,
  opts = {
    indent = { only_scope = true, chunk = true },
    statuscolumn = true,
    guide = { columns = { 121 }, char = "│" },
    -- Turn off your existing TextYankPost highlight before enabling this.
    feedback = { yank = false },
    focus = { width = 100, height = 0.9, dim = true },
    scrollbar = true,
  },
  config = function(_, opts)
    require("ui_tools").setup(opts)
    require("ui_tools.integrations.git_tools").setup()
  end,
  keys = {
    {
      "<leader><leader>",
      function()
        require("ui_tools").pulse()
      end,
      desc = "Pulse current line",
    },
    {
      "<leader>Z",
      function()
        require("ui_tools").zen()
      end,
      desc = "Toggle Zen mode",
    },
    {
      "<leader>z",
      function()
        require("ui_tools").zoom()
      end,
      desc = "Toggle Zoom",
    },
    {
      "<leader>tG",
      function()
        require("ui_tools").toggle("indent")
      end,
      desc = "Toggle indent guides",
    },
    {
      "<leader>tD",
      function()
        require("ui_tools").dim()
      end,
      desc = "Toggle scope dimming",
    },
  },
}
