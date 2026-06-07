if vim.g.loaded_my_plugin == 1 then
	return
end
vim.g.loaded_my_plugin = 1

vim.api.nvim_create_user_command("Pyglue", function()
	require("typst_pyglue").print_message()
end, { desc = "Prints the configured hello message" })
