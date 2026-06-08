local script = require("typst_pyglue.exescript")

local M = {
	lsp_cmd = nil,
	ltbufs = {},
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
			name = "pyglue_bglsp",
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
					vim.log.levels.WARN
				)
				return
			end
			local lines = vim.api.nvim_buf_get_lines(bufr.bufnr, 0, -1, false)
			print(
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
				vim.log.levels.DEBUG
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

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "typst")
	if not ok or not parser then
		vim.notify("typst-pyglue.nvim: Tree-sitter parser not available for this buffer.", vim.log.levels.ERROR)
		return
	end

	local tree = parser:parse()[1]
	local root = tree:root()

	local query = vim.treesitter.query.parse("typst", extraction_query)

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

		if not namespace or not code_text then
			vim.notify("typst-pyglue.nvim: Missing namespace or code capture in match.", vim.log.levels.ERROR)
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
			script.run_buf(bufr.bufnr, hbufs.reflection[bufr.bufnr].name)
		end
		::continue::
	end
end

function M.run_cursor()
	local mainbuf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)

	local row = cursor[1]

	if not M.ltbufs or not M.ltbufs[mainbuf] or not M.ltbufs[mainbuf][row] then
		vim.notify("typst-pyglue.nvim: No valid snippet found for the current line.", vim.log.levels.WARN)
		return
	end

	local bufr = M.ltbufs[mainbuf][row].bufr
	if bufr and vim.api.nvim_buf_is_valid(bufr.bufnr) then
		script.run_buf(bufr.bufnr, hbufs.reflection[bufr.bufnr].name)
	else
		vim.notify("typst-pyglue.nvim: No valid snippet found for the current line.", vim.log.levels.WARN)
	end
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

			for _, diag in ipairs(diagnostics) do
				local new_diag = diag

				new_diag.lnum = hbufs[mainbuf][name].chunk_rows[diag.lnum + 1] - 1

				new_diag.end_lnum = hbufs[mainbuf][name].chunk_rows[diag.end_lnum + 1] - 1

				if not new_diag.end_lnum or not new_diag.lnum then
					vim.notify(
						"typst-pyglue.nvim: Diagnostic missing end_lnum or num, skipping adjustment.",
						vim.log.levels.WARN
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

return M
