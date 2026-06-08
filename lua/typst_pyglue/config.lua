local M = {}

M.defaults = {
	create_keymaps = true,

	keys = {
		menu = { "<leader>P", group = "PyGlue Menu", icon = { icon = "󰌠 ", color = "yellow" } },
		run = { "<leader>Pr", desc = "Run All Code Snippets", icon = { icon = " ", color = "green" } },
		run_cursor = { "<leader>Pc", desc = "Run Snippet Under Cursor", icon = { icon = " ", color = "yellow" } },
	},

	python_lsp_cmd = { "pyright-langserver", "--stdio" },

	python_cmd = "python",
}

M.options = {}

return M
