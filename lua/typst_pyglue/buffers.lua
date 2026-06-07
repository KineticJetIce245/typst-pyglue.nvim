local M = {
	lsp_cmd = nil,
}

local hbufs = {}
local hbufstatus = true -- Global flag, a buffer that is unsynced will have the opposite value of this flag

local function getbuf(name)
	if not hbufs[name] then
		hbufs[name] = {
			status = hbufstatus,
			bufnr = vim.api.nvim_create_buf(false, true),
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
	end

	for name, bufr in pairs(hbufs) do
		if bufr.status ~= hbufstatus then -- Unsynced buffer
			vim.api.nvim_buf_delete(bufr.bufnr, { force = true }) -- Remove unsynced buffer
			hbufs[name] = nil -- Clear from our tracking table
			goto continue
		end

		if vim.api.nvim_buf_is_valid(bufr.bufnr) then
			vim.lsp.start({
				name = "pyglue_bglsp",
				cmd = M.lsp_cmd,
				root_dir = vim.fn.getcwd(),
			}, {
				bufnr = bufr.bufnr, -- CRITICAL: This keeps it out of your main buffer!
			})
		end
		::continue::
	end
end

local function printhbufs()
	for _, bufr in pairs(hbufs) do
		if not bufr.bufnr or not vim.api.nvim_buf_is_valid(bufr.bufnr) then
			print("Error: Hidden buffer does not exist.")
			return
		end

		local lines = vim.api.nvim_buf_get_lines(bufr.bufnr, 0, -1, false)

		print("Hidden Buffer Contents:")
		print(vim.inspect(lines))
	end
end

local injections = [[
((comment) @injection.content
  (#match? @injection.content "^/\\*\\s*@start")
  (#set! injection.language "python")
  (#offset! @injection.content 1 0 0 -2))
]]

function M.loadhl(opts)
	local ft = "typst"
	vim.treesitter.query.set(ft, "injections", injections)
end

local extraction_query = [[
  ((comment) @snippet
    (#match? @snippet "[@]start"))
]]

local function strip_content(content)
	local lines = {}
	for line in content:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	local snippet_name = lines[1]:match("@start%s*(%S+)") or "global"

	if #lines <= 2 then -- No content between start and end
		return snippet_name, {}
	end

	table.remove(lines, 1) -- Remove the first line ([@]start)
	table.remove(lines, #lines) -- Remove the last line

	return snippet_name, lines
end

function M.extract_snippet(bufnr)
	local snippets = {}

	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local ft = vim.bo[bufnr].filetype
	local lang = vim.treesitter.language.get_lang(ft) or ft

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
	if not ok or not parser then
		-- Tree not available
		return
	end

	local tree = parser:parse()[1]
	local root = tree:root()

	-- Parse our query
	local query = vim.treesitter.query.parse(lang, extraction_query)

	-- Iterate through all matched comments in the buffer
	for id, node in query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = query.captures[id]
		if capture_name == "snippet" then
			local start_row, _, end_row, _ = node:range()
			local name, lines = strip_content(vim.treesitter.get_node_text(node, bufnr))
			local chunk = {
				name = name,
				start_row = start_row,
				end_row = end_row,
				lines = lines,
			}
			if not snippets[name] then
				snippets[name] = {}
			end
			table.insert(snippets[name], chunk)
		end
	end

	syncbuf(snippets)
	printhbufs()
end

return M
