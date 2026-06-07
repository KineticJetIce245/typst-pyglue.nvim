local M = {
	lsp_cmd = nil,
}

local hbufs = {}
local hbufstatus = true -- Global flag, a buffer that is unsynced will have the opposite value of this flag
local bufsbin = {}

local function assign_buf() -- Recyle buffers if possible
	if #bufsbin > 0 then
		return table.remove(bufsbin) -- Recycle an old buffer
	else
		local newbuf = vim.api.nvim_create_buf(false, true) -- Create a new hidden buffer
		vim.api.nvim_set_option_value("filetype", "python", { buf = newbuf })

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

local function getbuf(name)
	if not hbufs[name] then
		hbufs[name] = {
			status = hbufstatus,
			bufnr = assign_buf(),
			chunk_rows = {},
		}
		vim.api.nvim_set_option_value("filetype", "python", { buf = hbufs[name].bufnr })
	end
	return hbufs[name]
end

local function syncbuf(snippets)
	-- Invert flag
	hbufstatus = not hbufstatus

	for name, chunks in pairs(snippets) do
		local bufr = getbuf(name)
		bufr.status = hbufstatus -- Sync status with the global flag
		local buflines = {}
		bufr.chunk_rows = {}
		for _, chunk in ipairs(chunks) do
			table.move(chunk.lines, 1, #chunk.lines, #buflines + 1, buflines)
			table.insert(bufr.chunk_rows, { chunk.start_row, chunk.end_row })
		end
		-- Fill up the buffer with the new lines
		vim.api.nvim_buf_set_lines(bufr.bufnr, 0, -1, false, buflines)
		local virtual_name = string.format("pyglue_virtual_%s.py", name)
		pcall(vim.api.nvim_buf_set_name, bufr.bufnr, virtual_name)
	end

	for name, bufr in pairs(hbufs) do
		if bufr.status ~= hbufstatus then -- Unsynced buffer
			table.insert(bufsbin, bufr.bufnr) -- Add to recycle bin
			vim.api.nvim_buf_set_lines(bufr.bufnr, 0, -1, false, {})
			hbufs[name] = nil -- Clear from tracking table
		end
	end
end

local function printhbufs()
	for name, bufr in pairs(hbufs) do
		if not bufr.bufnr or not vim.api.nvim_buf_is_valid(bufr.bufnr) then
			print("Error: Hidden buffer does not exist.")
			return
		end

		local lines = vim.api.nvim_buf_get_lines(bufr.bufnr, 0, -1, false)

		print("Hidden Buffer (", name, bufr.bufnr, ") Contents:")
		print(vim.inspect(lines))
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
	for line in content:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	if #lines <= 2 then -- No content between start and end
		return {}
	end

	table.remove(lines, 1) -- Remove the first line ([@]start)
	table.remove(lines, #lines) -- Remove the last line

	return lines
end

function M.extract_snippet(bufnr)
	local snippets = {}

	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "typst")
	if not ok or not parser then
		vim.notify("Error: Tree-sitter parser not available for this buffer.", vim.log.levels.ERROR)
		return
	end

	local tree = parser:parse()[1]
	local root = tree:root()

	local query = vim.treesitter.query.parse("typst", extraction_query)

	for pattern, match, metadata in query:iter_matches(root, bufnr, 0, -1) do
		local namespace = nil
		local code_text = nil
		local start_row, end_row = nil, nil

		-- Loop through the captures for this specific match
		for id, nodes in pairs(match) do
			local capture_name = query.captures[id]
			-- Neovim API quirk: `nodes` can sometimes be a table of nodes, or a single node.
			local node = type(nodes) == "table" and nodes[1] or nodes

			if capture_name == "python.namespace" then
				namespace = vim.treesitter.get_node_text(node, bufnr):gsub('"', "")
			elseif capture_name == "python.code" then
				code_text = vim.treesitter.get_node_text(node, bufnr)
				start_row, _, end_row, _ = node:range()
			end
		end

		if not namespace or not code_text then
			vim.notify("Error: Missing namespace or code capture in match.", vim.log.levels.ERROR)
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

	syncbuf(snippets)
	printhbufs()
end

return M
