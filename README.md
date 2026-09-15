# nvim-translate

A small Neovim translation and dictionary plugin. Its defaults use Alibaba
Cloud Model Studio's OpenAI-compatible API with Qwen3.7-Flash.

## Features

- Look up the word under the cursor as a learner's dictionary entry.
- Translate a Visual selection and explain only its useful sentence patterns
  and vocabulary.
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

The default configuration targets the Beijing region of Alibaba Cloud Model
Studio. Export the key before starting Neovim:

```sh
export DASHSCOPE_API_KEY="..."
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
      desc = "Translate or look up",
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
  api_key_env = "DASHSCOPE_API_KEY",
  base_url = nil,                      -- explicit value takes precedence
  base_url_env = "DASHSCOPE_BASE_URL",
  default_base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1",
  model = "qwen3.7-flash",

  temperature = 0.2,
  max_tokens = 2048,
  extra_body = {
    enable_thinking = false,
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

Qwen3.7-Flash enables thinking by default, so `enable_thinking = false` is sent
as a top-level request field. For another region or OpenAI-compatible provider,
override `base_url` (or `DASHSCOPE_BASE_URL`), `api_key_env`, `model`, and replace
`extra_body` with the fields accepted by that provider:

```lua
opts = {
  api_key_env = "MY_PROVIDER_API_KEY",
  base_url = "https://provider.example/v1",
  model = "provider-model",
  extra_body = {},
}
```

## Usage

- Invoke the configured mapping in Normal mode to look up `<cword>`.
- Invoke it in Visual mode to translate or look up the exact selection. A word
  or short fixed expression gets a dictionary card; a complete clause, sentence,
  dialogue, or paragraph gets the translation followed by useful language notes.
- Invoke it again while the floating window is open to focus the result for
  copying.
- Press `Esc` inside the result to close it.
- Run `:Translate` to translate the word under the cursor.

```lua
require("nvim-translate").translate()
require("nvim-translate").cancel()
require("nvim-translate").clear_cache()
```

Only the selected source text and the configured analysis prompt are sent to the
configured provider. The cache exists only for the current Neovim process.

## Tests

```sh
make test
```

## License status

The upstream repository does not currently declare a software license. This
fork does not attempt to choose one on the upstream author's behalf.
