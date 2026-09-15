# nvim-translate

A small Neovim translation and dictionary plugin. Its defaults use Alibaba
Cloud Model Studio's OpenAI-compatible API with Qwen3.7-Flash.

## Features

- Look up the word under the cursor as a compact learner's dictionary entry,
  with inflection metadata, part-of-speech pronunciation, grammar labels, and
  sense-local collocations and bilingual examples.
- Translate a Visual selection and explain only its useful sentence patterns
  and vocabulary.
- Enter text directly with `:TranslateInput`.
- Get ranked English candidates for a Chinese lexical item, with semantic
  distinctions and advice for naming data, actions, and types.
- Repeat the exact word as a Markdown headword, or a source passage in a styled
  callout.
- Stream complete Markdown lines into a fixed-size, focusable floating window,
  with throttled redraws, cancellation, and stale-response protection.
- Scroll the result with configurable source-buffer keys without entering the
  floating window, while preserving and restoring existing buffer mappings.
- Integrate automatically with render-markdown.nvim when it is configured for
  the `markdown` filetype.
- Keep successful results in a persistent local LRU cache, with independent,
  atomically written entries shared by multiple Neovim processes.
- Expose searchable history data and reopen a stored result without an API call,
  so picker integrations do not require a dependency in this plugin.
- Keep the API key and source text out of `curl` command-line arguments.
- Configure the endpoint, model, prompt, provider-specific request fields,
  timeouts, and window.

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
  cmd = { "Translate", "TranslateInput" },
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
  stream = true,
  extra_body = {
    enable_thinking = false,
  },
  prompt = "...",

  trigger_key = false,
  cache_enabled = true,
  max_cache_size = 100,
  cache_dir = vim.fn.stdpath("state") .. "/nvim-translate/cache",
  connect_timeout = 10,
  timeout = 45,

  title = " 翻译／词典 ",
  footer = "",
  border = "rounded",
  width = 84,                          -- ratio or absolute columns
  height = 28,                         -- ratio or absolute lines
  scroll_up_key = "<C-u>",            -- false disables either mapping
  scroll_down_key = "<C-d>",
  stream_update_interval = 160,
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
  After the selection is captured, the editor returns to Normal mode so result
  scrolling and focus keys work immediately.
- The exact source remains at the top of the floating window while streamed
  Markdown arrives below it. A word is rendered as the level-one headword;
  dictionary entries group lemma and inflection metadata, pronunciation, grammar,
  collocations, and bilingual examples like a learner's dictionary. Passages use
  separate translation and explanation sections.
- While focus remains in the source window, the default `<C-u>` and `<C-d>` keys
  scroll the translation result. These temporary buffer-local mappings are removed
  when the result closes, revealing any prior mapping or native behavior.
- Integrations can call `focus()` from an existing documentation key such as `K`
  to enter the result for selecting or copying.
- Invoke the configured translation mapping again from either window to close
  the current result and cancel an unfinished request.
- Press `Esc` inside the result to close it. Leaving a focused result window also
  closes it instead of leaving an unreachable floating window behind.
- Run `:Translate` to translate the word under the cursor.
- Run `:TranslateInput` to enter a word or sentence in `vim.ui.input`. The current
  UI provider can supply a floating input box. Cancelled or empty input sends no
  request. Use a Visual selection for multi-line input.
- Chinese words and short fixed expressions get ranked English candidates,
  each with pronunciation, semantic distinctions, collocations, a bilingual
  example, and advice on its suitability for data, action, or type naming.

```lua
require("nvim-translate").translate()
require("nvim-translate").translate("text entered by another integration")
require("nvim-translate").input()
require("nvim-translate").focus()
require("nvim-translate").cancel()
require("nvim-translate").clear_cache()
```

Only the selected source text, a `dictionary` or `auto` mode label, and the
configured analysis prompt are sent to the configured provider. Explicit text
uses `auto` classification and replaces an active result; context translation
without an argument retains its open/close toggle behavior.

## Local cache and history

Successful source text and Markdown results are stored under `cache_dir`. API
keys, errors, and incomplete responses are not stored. The default directory is
created with owner-only permissions, and entry files use mode `0600` on Unix.
Each entry is written independently via a same-directory temporary file and
atomic rename; history refreshes from disk to include other Neovim processes.

Cache identity includes the endpoint, model, prompt, generation options, request
mode, and exact source text. Changing the prompt or model does not reuse an old
answer, but that answer remains available in history until LRU eviction. Set
`cache_dir = false` for an in-memory-only cache, or `cache_enabled = false` to
skip automatic cache lookup and storage. `clear_cache()` removes stored entries
from the configured directory.

```lua
local translation = require("nvim-translate")
local entries = translation.history() -- newest access first, independent copies
if entries[1] then
  translation.open_history(entries[1].key) -- no model request
end
```

History entries contain `key`, `text`, `value` (the model's Markdown), `mode`,
`is_word` (the source presentation hint), and Unix microsecond `created_at` /
`used_at` timestamps. `markdown` is derived from the exact source and stored
result using the same presentation as the floating window. A picker can match
against `text` and `value`, preview `markdown`, and confirm with `open_history`.
The plugin does not require a picker library.

## Tests

```sh
make test
```

## License status

The upstream repository does not currently declare a software license. This
fork does not attempt to choose one on the upstream author's behalf.
