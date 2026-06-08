local M = {}

function M.run_buf(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("Error: Buffer " .. bufnr .. " does not exist.", vim.log.levels.ERROR)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local code = table.concat(lines, "\n")

	local result = vim.fn.system({ "python" }, code)
	vim.print("--- Output from Buffer " .. bufnr .. " ---\n" .. result)
end

return M
