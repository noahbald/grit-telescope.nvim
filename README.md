# grit-telescope.nvim

[Grit](https://github.com/getgrit/gritql) is query language used for searching and modifying documents.

## Getting started

Grit and Telescope need to be installed for this plugin to work

### Lazy

```lua
{
  "noahbald/grit-telescope.nvim"
}
```

## Features

This is still in early development and not all features you may want are available yet

- [x] Query using grit patterns and workflows
- [ ] Display preview of matches
- [ ] Display preview of modifications
- [ ] Action to apply a specific entry
- [ ] Action to apply all entries

## Configuration

This plugin wraps around the [apply](https://docs.grit.io/cli/reference#grit-apply) command. The preview always runs the command as a dry run, so no changes are applied without confirmation.
Read grit's reference to see the available options for configuration

```lua
{
  "noahbald/grit-telescope.nvim",
  -- NOTE: Not all these configuration options are available yet
  opts = {
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
