-- Point dir at your local checkout. Disable Snacks indent/statuscolumn, remove
-- its Zen/Zoom/dim mappings and dashboard, and disable nvim-scrollbar before using this spec.
return {
  dir = vim.fn.expand("~/Documents/Github/nvim_plugins/ui-tools.nvim"),
  name = "ui-tools.nvim",
  main = "ui_tools",
  lazy = false,
  opts = {
    dashboard = { layout = "vertical" }, -- or "horizontal"; both fit automatically
    indent = { only_scope = true, chunk = true },
    statuscolumn = true,
    guide = { columns = { 121 }, char = "│" },
    -- Turn off your existing TextYankPost highlight before enabling this.
    feedback = { yank = false },
    focus = { width = 100, height = 0.9, dim = true },
    scrollbar = true,
    context_menu = true,
  },
  config = function(_, opts)
    require("ui_tools").setup(opts)
    require("ui_tools.integrations.git_tools").setup()
    -- Optional: route menu actions through lsp-tools rather than the native UI.
    -- require("ui_tools.integrations.context_lsp").setup({
    --   actions = {
    --     definition = function() require("lsp-tools").lsp_definitions() end,
    --     references = function() require("lsp-tools").lsp_references() end,
    --     hover = function() require("lsp-tools").hover() end,
    --     rename = function() require("lsp-tools").rename() end,
    --     code_action = function() require("lsp-tools").code_action() end,
    --     diagnostic = function() require("lsp-tools").diagnostic() end,
    --   },
    -- })
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
