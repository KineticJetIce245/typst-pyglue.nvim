local M = {}

M.defaults = {
	create_keymaps = true,

	keys = {
		menu = { "<leader>P", group = "PyGlue Menu", icon = { icon = "󰌠 ", color = "white" } },
		run = { "<leader>Pr", desc = "Run All Code Snipets", icon = { icon = " ", color = "green" } },
	},

	python_lsp_cmd = { "pyright-langserver", "--stdio" },
}

M.options = {}

return M
