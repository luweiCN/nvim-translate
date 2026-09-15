# nvim-translate

A small Neovim translation plugin backed by DeepSeek or another
OpenAI-compatible Chat Completions API.

## Features

- Translate the word under the cursor or the current Visual selection.
- Show the result in a focusable Markdown floating window.
- Run requests asynchronously, with cancellation and stale-response protection.
- Cache repeated translations in memory with an LRU cache.
- Keep the API key and source text out of `curl` command-line arguments.
- Configure the endpoint, model, prompt, provider-specific request fields, timeouts,
  spinner, and window.

## Requirements

- Neovim 0.10 or newer
- curl 8.3 or newer (`--variable` and expanded options are required)
- An API key for the configured provider

## Installation

The default configuration targets DeepSeek. Export the key before starting
Neovim:

```sh
export DEEPSEEK_API_KEY="..."
```

With lazy.nvim:

```lua
{
  "luweiCN/nvim-translate",
  cmd = "Translate",
  keys = {
    {
      "<leader>ut",
      function()
        require("nvim-translate").translate()
      end,
      mode = { "n", "x" },
      desc = "Translate word or selection",
    },
  },
  opts = {},
}
```

The plugin does not create a keymap by default. Set `trigger_key` only when the
plugin itself should own the mapping.

## Defaults

```lua
{
  api_key = nil,                       -- string, function, or environment
  api_key_env = "DEEPSEEK_API_KEY",
  base_url = nil,                      -- explicit value takes precedence
  base_url_env = "DEEPSEEK_BASE_URL",
  default_base_url = "https://api.deepseek.com",
  model = "deepseek-flash",

  temperature = 0.2,
  max_tokens = 2048,
  extra_body = {
    thinking = { type = "disabled" },
  },
  prompt = "...",

  trigger_key = false,
  cache_enabled = true,
  max_cache_size = 100,
  connect_timeout = 10,
  timeout = 45,

  border = "rounded",
  max_width = 0.7,                     -- ratio or absolute columns
  max_height = 0.6,                    -- ratio or absolute lines
  spinner_frames = { "|", "/", "-", "\\" },
  spinner_interval = 120,
}
```

For another OpenAI-compatible provider, override `api_key_env`, `base_url`,
`model`, and replace `extra_body` with the fields accepted by that provider:

```lua
opts = {
  api_key_env = "MY_PROVIDER_API_KEY",
  base_url = "https://provider.example/v1",
  model = "provider-model",
  extra_body = {},
}
```

## Usage

- Invoke the configured mapping in Normal mode to translate `<cword>`.
- Invoke it in Visual mode to translate the exact selection.
- Invoke it again while the floating window is open to focus the result for
  copying.
- Press `Esc` inside the result to close it.
- Run `:Translate` to translate the word under the cursor.

```lua
require("nvim-translate").translate()
require("nvim-translate").cancel()
require("nvim-translate").clear_cache()
```

Only the selected source text and the translation prompt are sent to the
configured provider. The cache exists only for the current Neovim process.

## Tests

```sh
make test
```

## License status

The upstream repository does not currently declare a software license. This
fork does not attempt to choose one on the upstream author's behalf.
