local M = {}

function M.run_buf(python_cmd, bufnr, name)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("Buffer " .. bufnr .. " does not exist.", vim.log.levels.ERROR, { title = "typst-pyglue.nvim" })
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local code = table.concat(lines, "\n")

	local result = vim.fn.system({ python_cmd }, code):gsub("\n$", "")
	vim.notify(result, vim.log.levels.INFO, {
		title = "typst-pyglue.nvim: " .. 'Outputs from "' .. name .. '"',
	})
end

return M
