# typst-pyglue.nvim
**typst-pyglue.nvim** is a **Neovim** plugin that allows you to write and execute **Python** code snippets directly inside of your **Typst** files without needing to switch tabs or open a terminal.

## ✨ Features
- **In-Buffer Execution**:
  - You can run Python codes **directly** from your Typst document.
- **LSP Support**:
  - It is compatible with Python LSP (e.g., Pyright).
- **Namespace *Glueing***:
  - You can define multiple code snippets. They are treated as **different files** by the LSP.
  - You can **glue** fragmented code snippets together by putting them in the same namespace, preserving variables and context across your document.
- **Autocompletion**:
  - It supports **autocompletion** with `blink.cmp`.

## 📦 Installation
Install typst-pyglue using your preferred package manager.
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
    python_lsp_cmd = { "pyright-langserver", "--stdio" },
    create_keymaps = true,
    keys = {
      run = { "<leader>Pr", desc = "Run all python snippets" },
    }
  }
}
```

## 💻 Usage
At the start of your Typst document, define an empty function called `pyglue` with the parameters `name` and `code` so the code blocks are not rendered.
```typst
#let pyglue(name, code) = {}
```
To can define code snippets as follows:
````typst
#pyglue("space1", ```python
x = 10
print("First part of the code snippet")
```)

#pyglue("space2", ```python
x = 1
print("Name space 2")
print(x)
```)

#pyglue("space1", ```python
print("Second part of the code snippet")
print(x)
```)
````
For the code above, **typst-pyglue.nvim** will *glue* the first and second part of `space1` together, while it is separated from `space2`.
