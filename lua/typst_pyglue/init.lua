local config = require("typst_pyglue.config")
local buffers = require("typst_pyglue.buffers")

local M = {
	proxied_lsp = {},
}

M.run_allbufs = buffers.run_allbufs
M.run_name = buffers.run_name
M.run_cursor = buffers.run_cursor

M.setup = function(opts)
	config.options = vim.tbl_deep_extend("force", config.defaults, opts or {})

	buffers.python_cmd = config.options.python_cmd
	buffers.lsp_cmd = config.options.python_lsp_cmd
	buffers.setup_diags()

	if config.options.create_keymaps then
		-- Run all code snippets
		vim.keymap.set("n", config.options.keys.run[1], buffers.run_allbufs, {
			desc = config.options.keys.run.desc,
			noremap = true,
			silent = false,
		})

		vim.keymap.set("n", config.options.keys.run_cursor[1], buffers.run_cursor, {
			desc = config.options.keys.run_cursor.desc,
			noremap = true,
			silent = false,
		})

		-- which-key integration
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

	-- Buffer extractions
	local tpgroup = vim.api.nvim_create_augroup("TypstPyglue", { clear = true })
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "TextChanged", "TextChangedI" }, {
		group = tpgroup,
		pattern = "*.typ",
		callback = function(args)
			buffers.extract_snippet(args.buf)
		end,
	})

	-- Setup LSP proxying on attach
	vim.api.nvim_create_autocmd("LspAttach", {
		group = tpgroup,
		pattern = "*.typ",
		callback = function(args)
			local main_bufnr = args.buf
			local client = vim.lsp.get_client_by_id(args.data.client_id)

			-- Filter: Only proceed if the attached client is a Typst LSP
			if not client or (client.name ~= "tinymist" and client.name ~= "typst_lsp") then
				return
			end

			print("Attaching typst-pyglue proxy to LSP client:", client.name)

			if M.proxied_lsp[client.id] then
				return
			end
			M.proxied_lsp[client.id] = true

			buffers.setup_proxy_to_lsp(client)
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = tpgroup,
		pattern = "*.typ",
		callback = function(args)
			local client_id = args.data.client_id
			if M.proxied_lsp[client_id] then
				M.proxied_lsp[client_id] = nil
			end
		end,
	})
end

return M
