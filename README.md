# typst-pyglue.nvim
**typst-pyglue.nvim** is a **Neovim** plugin that allows you to write and execute **Python** code snippets directly inside of your **Typst** files without needing to switch tabs or open a terminal.

## ✨ Features
- **In-Buffer Execution**:
  - You can run Python codes **directly** from your Typst document.
- **LSP Support**:
  - It is compatible with Python LSP (e.g., Pyright).
  - **Supports**:
    - Diagnostics, document highlights (for variables)
    - Jump to definition, reference
    - Signture help, hover
- **Autocompletion**:
  - It supports **autocompletion** with `blink.cmp` (source file called `blink_source.lua`)
- **Namespace *Gluing***:
  - You can define multiple code snippets. They are treated as **different files** by the LSP.
  - You can **glue** fragmented code snippets together by putting them in the same namespace, preserving variables and context across your document.

## 💻 Usage
To use the plugin, you need to first define the `#pyglue` function at the top of your documents
```typst
#let pyglue(namespace, code) = {
// You can leave it empty so the code is not rendered
}
```
To write and execute the codes, you must provide a "namespace" as the first argument, followed by the Python code block.
The plugin will automatically _glue_ code blocks that share the same namespace. This allows you to write continuous scripts that are broken up by Typst text, without losing your variable state or context.

### Example
Here is how you might structure a Typst document with multiple interleaved Python scripts:
````typst
= Data Analysis

First, we initialize our main variables in `space1`.

#pyglue("space1", ```python
x = 10
print("First part of the code snippet")
```)

Sometimes, we need an entirely isolated script for a diagram or helper function. We can put this in `space2`.

#pyglue("space2", ```python
x = 1
print("Namespace 2 running independently...")
print(f"x is {x}")
```)

Now, we can return to `space1`. The state is preserved, so it remembers the value of `x` we defined earlier!

#pyglue("space1", ```python
print("Second part of the code snippet")
print(f"x is still {x}")
```)
````
**Executing the Code**:\
You can run these isolated namespaces directly from Neovim. Because the execution is strictly isolated by namespace, evaluating them will capture the output and display it via `vim.notify`.
- Running `space1` will pop up a notification showing:
  ```
  First part of the code snippet
  Second part of the code snippet
  x is still 10
  ```
- Running `space2` will pop up a notification showing:
  ```
  Namespace 2 running independently...
  x is 1
  ```

## 📦 Installation
Install typst-pyglue using your preferred package manager. It requires [`nvim-treesitter/nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter) and [`Saghen/blink.cmp`](https://github.com/saghen/blink.cmp).
Using lazy.nvim:
```Lua
{
  "KineticJetIce245/typst-pyglue.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "Saghen/blink.cmp",
  },
  ft = "typst",
  opts = {
    -- leave it empty to use the default settings
    -- refer to the configuration section below
    python_cmd = "python3" 
  }
}
```

## ⚙️ Configuration
### Configurations for typst-pyglue.nvim
The default configuration is as follows:
```Lua
opts = {
  -- create hotkeys
	create_keymaps = true,
  -- hotkeys
	keys = {
		menu = { "<leader>P", group = "PyGlue Menu" },
		run = { "<leader>Pr", desc = "Run All Code Snippets" },
		run_cursor = { "<leader>Pc", desc = "Run Snippet Under Cursor" },
	},
  -- choice of LSP
	python_lsp_cmd = { "pyright-langserver", "--stdio" }, 
  -- command to start python, e.g. use python3 for MacOs or Linux
	python_cmd = "python", 
}
```
### Configurations for blink.cmp
To set up `blink.cmp`, one can use the following configuration for `blink.cmp`:
```Lua
  {
    "saghen/blink.cmp",
    dependencies = { "typst-pyglue.nvim" },

    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.default = opts.sources.default or { "lsp", "path", "snippets", "buffer" }
      opts.sources.providers = opts.sources.providers or {}

      if not vim.tbl_contains(opts.sources.default, "typst_pyglue") then
        table.insert(opts.sources.default, "typst_pyglue")
      end

      opts.sources.providers.typst_pyglue = {
        name = "typst_pyglue",
        module = "typst_pyglue.blink_source",
        score_offset = 100,
        async = true,
      }
    end,
  },
```

## ❔ How It Works
This plugin slices out the code blocks in your Typst document and glues them together into hidden buffers.
- **Syntax Extraction**: The plugin scans your active Typst file for the `#pyglue` syntax and extracts the inner Python code alongside its declared namespace.
- **Namespace Gluing**: It collects all fragemented code blocks that share the exact same namespace string and glues them together in sequential order.
- **Buffer Isolation**: The concatenated code for each unique namespace is sent to its own _dedicated, hidden Neovim buffer_.
- **Native LSP Support**: Because the code is now residing in standard Python buffers behind the scenes, your Neovim Python LSP (like pyright or pylsp) treats each namespace as a distinct, valid Python file. This means you get full diagnostics perfectly scoped to that specific namespace, with no mixing between isolated scripts.
- **Execution & Notification**: When triggered, the plugin executes the hidden buffer corresponding to your chosen namespace. It captures the standard output and shows the results directly in your editor using Neovim's native vim.notify API.

### 💡 Acknowledgements / Inspiration
This plugin is heavily inspired by [`jmbuhr/otter.nvim`](https://github.com/jmbuhr/otter.nvim).
