# grit-telescope.nvim

[Grit](https://github.com/getgrit/gritql) is query language used for searching and modifying documents.

## Getting started

Grit and Telescope need to be installed for this plugin to work

![Recording of using gritql for a basic match query](https://github.com/noahbald/grit-telescope.nvim/assets/36181524/bc238c7a-4dce-4017-98fe-cec34a50e88b)

### Lazy

```lua
{
  "noahbald/grit-telescope.nvim"
}
```

## Features

If you think a feature is missing, please create an issue for it :)

- Query using grit patterns and workflows
- Display preview of matches
- Display preview of modifications
- Action to apply a specific entry
- Action to apply all entries (Note, only works for future version of grit)

## Usage

```vi
:Telescope grit
```

| key         | action                              |
| ----------- | ----------------------------------- |
| `<C-space>` | Apply replacement to selected entry |
| `<C-f>`     | Apply replacement to selected file  |
| `<C-a>`     | Apply replacement to all files      |

## Configuration

This plugin wraps around the [apply](https://docs.grit.io/cli/reference#grit-apply) command. The preview always runs the command as a dry run, so no changes are applied without confirmation.

Read grit's reference to see the available options for configuration

```lua
{
  "noahbald/grit-telescope.nvim",
  -- NOTE: Not all these configuration options are available yet
  opts = {
    -- Change the directory patterns are queried on
    cwd = vim.loop.cwd()
    -- Change the default language to use for the pattern.
    language = "js",
    -- Interpret the request as a natural language request.
    ai = false,
  },
  -- NOTE: Keys are not provided by default
  keys = {
    { "<leader>fq", "<cmd>Telescope grit<cr>", desc = "Telescope Grit Query" },
  }
}
```
