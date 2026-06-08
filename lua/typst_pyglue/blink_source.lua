local buffers = require("typst_pyglue.buffers")
local source = {}

function source.new()
	return setmetatable({}, { __index = source })
end

function source:enable()
	return true
end

function source:get_completions(context, callback)
	local main_bufnr = vim.api.nvim_get_current_buf()
	local main_row = context.cursor[1]
	local main_col = context.cursor[2]

	if not buffers.ltbufs or not buffers.ltbufs[main_bufnr] or not buffers.ltbufs[main_bufnr][main_row] then
		callback()
		return
	end

	local bufr = buffers.ltbufs[main_bufnr][main_row].bufr
	local linhbuf = buffers.ltbufs[main_bufnr][main_row].lnum

	if not bufr then
		vim.notify("No valid snippet found for current line.", vim.log.levels.WARN, { title = "typst-pyglue.nvim" })
		callback()
		return
	end

	local params = {
		textDocument = { uri = vim.uri_from_bufnr(bufr.bufnr) },
		position = {
			line = linhbuf - 1, -- 0 indexed
			character = main_col,
		},
	}

	local clients = vim.lsp.get_clients({ bufnr = bufr.bufnr })
	if #clients == 0 then
		callback()
		return
	end

	local client = clients[1]

	local _, request_id = client:request("textDocument/completion", params, function(err, result)
		if err or not result then
			callback()
			return
		end

		local items = result.items or result

		for _, item in ipairs(items) do
			if item.textEdit then
				local edit_range = item.textEdit.range or item.textEdit.insert
				if edit_range then
					local ldiff = edit_range["end"].line - edit_range.start.line
					edit_range.start.line = main_row - 1
					edit_range["end"].line = main_row - 1 + ldiff
				end
			end

			if item.additionalTextEdits then
				for _, additional_edit in ipairs(item.additionalTextEdits) do
					additional_edit.range.start.line = bufr.chunk_rows[additional_edit.range.start.line + 1] - 1
					additional_edit.range["end"].line = bufr.chunk_rows[additional_edit.range["end"].line + 1] - 1
				end
			end
		end

		callback({
			is_incomplete_forward = result.isIncomplete or false,
			is_incomplete_backward = result.isIncomplete or false,
			items = items,
		})
	end, bufr.bufnr)

	return function()
		if request_id then
			client:cancel_request(request_id)
		end
	end
end

return source
