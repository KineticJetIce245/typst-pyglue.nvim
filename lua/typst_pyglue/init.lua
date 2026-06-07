local config = require("typst_pyglue.config")
local buffers = require("typst_pyglue.buffers")

local M = {}

local function print_message()
	print("hello world")
end

M.print_message = print_message

M.setup = function(opts)
	config.options = vim.tbl_deep_extend("force", config.defaults, opts or {})
	-- spin up lsp client
	buffers.lsp_cmd = config.options.python_lsp_cmd
	buffers.loadhl()

	if config.options.create_keymaps then
		-- Run all code snippets
		vim.keymap.set("n", config.options.keys.run[1], M.print_message, {
			desc = config.options.keys.run.desc,
			noremap = true,
			silent = false,
		})

		-- Add which-key integration
		local wk_ok, wk = pcall(require, "which-key")
		if wk_ok then
			local wk_maps = {}
			for k, v in pairs(config.options.keys) do
				if k == "menu" then
					table.insert(wk_maps, { v[1], group = v.group, icon = v.icon })
				else
					table.insert(wk_maps, { v[1], icon = v.icon })
				end
			end
			wk.add(wk_maps)
		end
	end

	-- Buffer Extractions
	local mbufextra = vim.api.nvim_create_augroup("LiveSnippetExtractor", { clear = true })
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "TextChanged", "TextChangedI" }, {
		group = mbufextra,
		pattern = "*.typ",
		callback = function(args)
			buffers.extract_snippet(args.buf)
		end,
	})

	local original_comments = vim.bo.comments
	local tscc = vim.api.nvim_create_augroup("TsCustomCommentBehavior", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMovedI", "InsertEnter" }, {
		group = tscc,
		pattern = "*.typ",
		callback = function()
			local buf = vim.api.nvim_get_current_buf()

			local has_parser, parser = pcall(vim.treesitter.get_parser, buf)
			if not has_parser or not parser then
				return
			end

			local row, col = unpack(vim.api.nvim_win_get_cursor(0))
			row = row - 1

			local root_tree = parser:parse()[1]
			local root_node = root_tree:root()
			local node = root_node:named_descendant_for_range(row, col, row, col)

			local in_snippet = false

			-- 3. Check if the cursor is inside a comment node
			if node and node:type() == "comment" then
				-- Fetch the full text of just this comment node
				local text = vim.treesitter.get_node_text(node, buf)

				-- Match your custom trigger at the very start of the comment block
				if text:match("^/%*%s*@start") then
					in_snippet = true
				end
			end

			if in_snippet then
				local cleaned = vim.bo.comments:gsub("mb:%*,?", ""):gsub(",?ex:%*/", "")
				vim.bo.comments = cleaned
			else
				vim.bo.comments = original_comments
			end
		end,
	})
end

return M
