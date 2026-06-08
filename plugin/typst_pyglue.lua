if vim.g.loaded_my_plugin == 1 then
	return
end
vim.g.loaded_my_plugin = 1

vim.api.nvim_create_user_command("PyglueRun", function()
	require("typst_pyglue").run_allbufs()
end, { desc = "Run All Code Snippets" })
