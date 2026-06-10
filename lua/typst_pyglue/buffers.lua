local script = require("typst_pyglue.exescript")

local M = {
	lsp_cmd = nil,
	ltbufs = {},
	python_cmd = nil,
}

local hbufs = {
	reflection = {},
	status = {},
}
local bufsbin = {} -- Recyclin bin

local function assign_buf() -- Recyle buffers if possible
	if #bufsbin > 0 then
		return table.remove(bufsbin) -- Recycle an old buffer
	else
		local newbuf = vim.api.nvim_create_buf(false, true) -- Create a new hidden buffer
		local virtual_name = string.format(".virtual.%s.py", newbuf)
		vim.api.nvim_set_option_value("filetype", "python", { buf = newbuf })
		vim.api.nvim_buf_set_name(newbuf, virtual_name)

		vim.lsp.start({
			name = "pyglue_background_ls",
			cmd = M.lsp_cmd,
			root_dir = vim.fn.getcwd(),
		}, {
			bufnr = newbuf,
		})

		return newbuf
	end
end

local function getbuf(mainbuf, name)
	if not hbufs[mainbuf] then
		hbufs[mainbuf] = {}
	end
	if not hbufs[mainbuf][name] then
		hbufs[mainbuf][name] = {
			status = hbufs.status[mainbuf], -- Sync with the global flag
			bufnr = assign_buf(),
			chunk_rows = {},
		}
		hbufs.reflection[hbufs[mainbuf][name].bufnr] = { mainbuf = mainbuf, name = name } -- Add to reflection table
	end
	hbufs[mainbuf][name].status = hbufs.status[mainbuf] -- Ensure the buffer's status is in sync with the global flag
	return hbufs[mainbuf][name]
end

local function unassign_buf(mainbuf, bufnr)
	local name = hbufs.reflection[bufnr].name

	-- Needs to clear diagnostics before unassigning
	local diag_namespace = vim.api.nvim_create_namespace("pyglue" .. name)
	if vim.api.nvim_buf_is_valid(mainbuf) then
		vim.diagnostic.set(diag_namespace, mainbuf, {})
	end

	table.insert(bufsbin, bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

	hbufs[mainbuf][name] = nil
	hbufs.reflection[bufnr] = nil
end

local function syncbuf(mainbuf, snippets)
	M.ltbufs[mainbuf] = {} -- Reset line-to-buffer mapping for cmp
	-- Invert flag
	if hbufs.status[mainbuf] == nil then
		hbufs.status[mainbuf] = true -- Initialize on first run
	end
	hbufs.status[mainbuf] = not hbufs.status[mainbuf]

	for name, chunks in pairs(snippets) do
		local bufr = getbuf(mainbuf, name)
		local buflines = {}
		bufr.chunk_rows = {}
		for _, chunk in ipairs(chunks) do
			for i, line in ipairs(chunk.lines) do
				table.insert(buflines, line)
				table.insert(bufr.chunk_rows, chunk.start_row + i + 1)
				M.ltbufs[mainbuf][chunk.start_row + i + 1] = { lnum = #bufr.chunk_rows, bufr = bufr }
			end
		end
		-- Extra line at the end to prevent out-of-bounds errors in diagnostics
		if #bufr.chunk_rows > 0 then
			table.insert(bufr.chunk_rows, bufr.chunk_rows[#bufr.chunk_rows] + 1)
		end
		-- Fill up the buffer with the new lines
		vim.api.nvim_buf_set_lines(bufr.bufnr, 0, -1, false, buflines)
	end

	if not hbufs[mainbuf] then
		return
	end

	for _, bufr in pairs(hbufs[mainbuf]) do
		if bufr.status ~= hbufs.status[mainbuf] then -- Unsynced buffer
			unassign_buf(mainbuf, bufr.bufnr)
		end
	end
end

function M.printhbufs()
	for mbuf, _ in pairs(hbufs) do
		if mbuf == "reflection" or mbuf == "status" then
			goto continue
		end

		for name, bufr in pairs(hbufs[mbuf]) do
			if not bufr.bufnr or not vim.api.nvim_buf_is_valid(bufr.bufnr) then
				vim.notify(
					"Hidden buffer" .. bufr.bufnr .. " for " .. mbuf .. ":" .. name .. " is invalid or missing.",
					vim.log.levels.WARN,
					{ title = "typst-pyglue.nvim" }
				)
				return
			end
			local lines = vim.api.nvim_buf_get_lines(bufr.bufnr, 0, -1, false)
			vim.notify(
				"Hidden Buffer from "
					.. mbuf
					.. ": ("
					.. name
					.. " "
					.. bufr.bufnr
					.. ") \n"
					.. vim.inspect(bufr.chunk_rows)
					.. "\n"
					.. vim.inspect(lines),
				vim.log.levels.DEBUG,
				{ title = "typst-pyglue.nvim" }
			)
		end
		::continue::
	end
end

local extraction_query = [[
  (call
    item: (ident) @func_name (#eq? @func_name "pyglue")
    (group 
      (string) @python.namespace
      (raw_blck) @python.code))
]]

local function strip_content(content)
	local lines = {}

	content = content .. "\n"
	for line in content:gmatch("(.-)\r?\n") do
		table.insert(lines, line)
	end

	if #lines <= 2 then -- No content between start and end
		return {}
	end

	table.remove(lines, 1)
	table.remove(lines, #lines)

	return lines
end

function M.extract_snippet(bufnr)
	local snippets = {}

	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local tree_ok, parser = pcall(vim.treesitter.get_parser, bufnr, "typst")
	if (not tree_ok) or not parser then
		vim.notify(
			"Tree-sitter parser not available for this buffer.",
			vim.log.levels.ERROR,
			{ title = "typst-pyglue.nvim" }
		)
		return
	end

	local tree = parser:parse()[1]
	local root = tree:root()

	local query_okay, query = pcall(vim.treesitter.query.parse, "typst", extraction_query)
	if (not query_okay) or not query then
		vim.notify(
			"Failed to parse Tree-sitter query: " .. tostring(query),
			vim.log.levels.ERROR,
			{ title = "typst-pyglue.nvim" }
		)
		return
	end

	for _, match, _ in query:iter_matches(root, bufnr, 0, -1) do
		local namespace = nil
		local code_text = nil
		local start_row, end_row = nil, nil

		for id, nodes in pairs(match) do
			local capture_name = query.captures[id]
			local node = type(nodes) == "table" and nodes[1] or nodes

			if capture_name == "python.namespace" then
				namespace = vim.treesitter.get_node_text(node, bufnr):gsub('"', "")
				if namespace == "" then
					namespace = "global"
				end
			elseif capture_name == "python.code" then
				code_text = vim.treesitter.get_node_text(node, bufnr)
				start_row, _, end_row, _ = node:range()
			end
		end

		if (not namespace) or not code_text then
			vim.notify(
				"Missing namespace or code capture in match.",
				vim.log.levels.ERROR,
				{ title = "typst-pyglue.nvim" }
			)
			return
		end

		local lines = strip_content(code_text)
		local chunk = {
			name = namespace,
			start_row = start_row,
			end_row = end_row,
			lines = lines,
		}
		if not snippets[namespace] then
			snippets[namespace] = {}
		end
		table.insert(snippets[namespace], chunk)
	end

	syncbuf(bufnr, snippets)
end

function M.run_allbufs()
	for mainbuf, _ in pairs(hbufs) do
		if mainbuf == "reflection" or mainbuf == "status" then
			goto continue
		end
		for _, bufr in pairs(hbufs[mainbuf]) do
			script.run_buf(M.python_cmd, bufr.bufnr, hbufs.reflection[bufr.bufnr].name)
		end
		::continue::
	end
end

function M.run_cursor()
	local mainbuf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)

	local row = cursor[1]

	if (not M.ltbufs) or not M.ltbufs[mainbuf] or not M.ltbufs[mainbuf][row] then
		vim.notify("No valid snippet found for the current line.", vim.log.levels.WARN, { title = "typst-pyglue.nvim" })
		return
	end

	local bufr = M.ltbufs[mainbuf][row].bufr
	if bufr and vim.api.nvim_buf_is_valid(bufr.bufnr) then
		script.run_buf(M.python_cmd, bufr.bufnr, hbufs.reflection[bufr.bufnr].name)
	else
		vim.notify("No valid snippet found for the current line.", vim.log.levels.WARN, { title = "typst-pyglue.nvim" })
	end
end

function M.run_name(name)
	local mainbuf = vim.api.nvim_get_current_buf()
	local bufnr = hbufs[mainbuf] and hbufs[mainbuf][name] and hbufs[mainbuf][name].bufnr
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("No valid snippet found for name: " .. name, vim.log.levels.WARN, { title = "typst-pyglue.nvim" })
		return
	end
	script.run_buf(M.python_cmd, bufnr, name)
end

function M.setup_diags()
	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		callback = function(args)
			if hbufs.reflection[args.buf] == nil then
				return
			end

			local mainbuf = hbufs.reflection[args.buf].mainbuf
			local diagnostics = vim.diagnostic.get(args.buf)
			local name = hbufs.reflection[args.buf].name

			if (not mainbuf) or not diagnostics or not name then
				vim.notify(
					"Missing mainbuf, diagnostics, or name for buffer "
						.. args.buf
						.. ". Skipping diagnostic adjustment.",
					vim.log.levels.WARN,
					{ title = "typst-pyglue.nvim" }
				)
				return
			end

			for _, diag in ipairs(diagnostics) do
				local new_diag = diag

				new_diag.lnum = hbufs[mainbuf][name].chunk_rows[diag.lnum + 1] - 1
				new_diag.end_lnum = hbufs[mainbuf][name].chunk_rows[diag.end_lnum + 1] - 1

				if (not new_diag.end_lnum) or not new_diag.lnum then
					vim.notify(
						"Diagnostic missing end_lnum or num, skipping adjustment.",
						vim.log.levels.WARN,
						{ title = "typst-pyglue.nvim" }
					)
				end

				if new_diag.lnum < 0 then
					new_diag.lnum = 0
				end

				if new_diag.end_lnum < 0 then
					new_diag.end_lnum = 0
				end
			end

			local diag_namespace = vim.api.nvim_create_namespace("pyglue" .. name)
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(mainbuf) then
					vim.diagnostic.set(diag_namespace, mainbuf, diagnostics)
				end
			end)
		end,
	})
end

local function proxy_result(method, result, hbuf, mainbufnr)
	local hbufnr = hbuf.bufnr
	if (not result) or vim.tbl_isempty(result) then
		return result
	end

	local main_uri = vim.uri_from_bufnr(mainbufnr)

	local function translate_range(range)
		if not range then
			return range
		end

		local new_range = vim.deepcopy(range)
		new_range.start.line = hbuf.chunk_rows[range.start.line + 1] - 1
		new_range["end"].line = hbuf.chunk_rows[range["end"].line + 1] - 1

		return new_range
	end

	local function translate_location(loc)
		local is_loc = loc.uri ~= nil
		local uri = is_loc and loc.uri or loc.targetUri
		if not uri then
			return loc
		end

		if vim.uri_to_bufnr(uri) == hbufnr then
			local new_loc = vim.deepcopy(loc)

			if is_loc then
				new_loc.uri = main_uri
				new_loc.range = translate_range(loc.range)
			else
				new_loc.targetUri = main_uri
				new_loc.targetRange = translate_range(loc.targetRange)
				new_loc.targetSelectionRange = translate_range(loc.targetSelectionRange)
			end

			return new_loc
		end

		return loc
	end

	if
		method == "textDocument/definition"
		or method == "textDocument/declaration"
		or method == "textDocument/typeDefinition"
		or method == "textDocument/implementation"
		or method == "textDocument/references"
	then
		if vim.islist(result) then
			local translated_list = {}
			for _, loc in ipairs(result) do
				table.insert(translated_list, translate_location(loc))
			end
			return translated_list
		else
			return translate_location(result)
		end
	elseif method == "textDocument/hover" then
		local new_hover = vim.deepcopy(result)
		new_hover.range = translate_range(result.range)
		return new_hover
	elseif method == "textDocument/documentHighlight" then
		local new_highlights = vim.deepcopy(result)
		for _, highlight in pairs(new_highlights) do
			highlight.range = translate_range(highlight.range)
		end
		return new_highlights
	elseif method == "textDocument/rename" then
		local is_changes = result.changes ~= nil
		local changes = is_changes and result.changes or result.documentChanges
		if not changes then
			return result
		end
		local new_edit = vim.deepcopy(result)
		local entries = is_changes and new_edit.changes or new_edit.documentChanges

		for _, entry in pairs(entries) do
			local is_uri, uribufnr = pcall(vim.uri_to_bufnr, entry.textDocument.uri)
			if (not is_uri) or not uribufnr or (uribufnr ~= hbufnr) then
				goto continue
			end
			entry.textDocument.uri = main_uri
			for _, edit in pairs(entry.edits) do
				edit.range = translate_range(edit.range)
			end
			::continue::
		end
		return new_edit
	end

	return result
end

function M.setup_proxy_to_lsp(client)
	local original_request = client.request
	client.request = function(self, method, params, handler, bufnr)
		-- Get the buffer number from params or use the current buffer as fallback
		if (not bufnr) or (bufnr == 0) then
			if params and params.textDocument and params.textDocument.uri then
				bufnr = vim.uri_to_bufnr(params.textDocument.uri)
			else
				bufnr = vim.api.nvim_get_current_buf()
			end
		end

		local cursor_loc = vim.api.nvim_win_get_cursor(0)

		-- Check if cursor is within a snippet and if the request is position-based.
		if (not M.ltbufs) or not M.ltbufs[bufnr] or not M.ltbufs[bufnr][cursor_loc[1]] then
			return original_request(self, method, params, handler, bufnr)
		end
		-- Requests that are based on the cursor position
		local position_based_methods = {
			-- Navigation
			["textDocument/definition"] = true,
			["textDocument/declaration"] = true,
			["textDocument/typeDefinition"] = true,
			["textDocument/implementation"] = true,
			["textDocument/references"] = true,
			["textDocument/documentHighlight"] = true,
			-- UI / Information
			["textDocument/hover"] = true,
			["textDocument/signatureHelp"] = true,
			-- Edits
			["textDocument/rename"] = true,
		}

		-- Chekc if the method is one of the position-based methods we want to proxy.
		if not position_based_methods[method] then
			return original_request(self, method, params, handler, bufnr)
		end

		if params and type(params) == "table" and params.position then
			-- Obtain bufnr from the main buffer row position
			local hbuf = M.ltbufs[bufnr][cursor_loc[1]].bufr
			local hbufnr = hbuf.bufnr
			local hclient = vim.lsp.get_clients({ bufnr = hbufnr })[1]

			if not hclient then
				vim.notify(
					"No LSP client attached to hidden buffer " .. hbufnr .. ". Cannot proxy request.",
					vim.log.levels.WARN,
					{ title = "typst-pyglue.nvim" }
				)
				return original_request(self, method, params, handler, bufnr)
			end

			local hidden_params = vim.deepcopy(params)

			-- Override the textDocument.uri to point to the hidden buffer and adjust the position
			hidden_params.textDocument.uri = vim.uri_from_bufnr(hbufnr)
			hidden_params.position.line = M.ltbufs[bufnr][params.position.line + 1].lnum - 1

			-- handler could be nil for some methods
			local actual_handler = handler or self.handlers[method] or vim.lsp.handlers[method]
			-- Fire the request on the hidden buffer's LSP client
			return hclient:request(method, hidden_params, function(err, result, ctx, config)
				if err or not result then
					return actual_handler(err, result, ctx, config)
				end
				local translated_result = proxy_result(method, result, hbuf, bufnr)
				-- Override the contexts
				ctx.bufnr = bufnr
				ctx.client_id = client.id
				ctx.params = params
				actual_handler(err, translated_result, ctx, config)
			end, hbufnr)
		end

		-- Non table params or missing position, fallback to original request
		return original_request(self, method, params, handler, bufnr)
	end
end

return M
