local plugin = require("typst_pyglue")

if vim.g.loaded_my_plugin == 1 then
	return
end
vim.g.loaded_my_plugin = 1

vim.api.nvim_create_user_command("PyglueRunAll", function()
	plugin.run_allbufs()
end, { desc = "Run All Code Snippets" })

vim.api.nvim_create_user_command("PyglueRun", function(opts)
	local name = opts.fargs[1]
	plugin.run_name(name)
end, {
	nargs = 1,
	desc = "Run Code Snippets in Current Buffer",
})
