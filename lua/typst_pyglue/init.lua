local config = require("typst_pyglue.config")
local buffers = require("typst_pyglue.buffers")

local M = {}

M.setup = function(opts)
	config.options = vim.tbl_deep_extend("force", config.defaults, opts or {})

	buffers.lsp_cmd = config.options.python_lsp_cmd
	buffers.setup_diags()

	if config.options.create_keymaps then
		-- Run all code snippets
		vim.keymap.set("n", config.options.keys.run[1], buffers.run_allbufs, {
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
end

return M
