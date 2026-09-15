local cache = require("nvim-translate.cache")
local config = require("nvim-translate.config")

local M = {}
local mapped_key

local function remove_mapping()
  if not mapped_key then
    return
  end
  for _, mode in ipairs({ "n", "x" }) do
    pcall(vim.keymap.del, mode, mapped_key)
  end
  mapped_key = nil
end

function M.setup(opts)
  require("nvim-translate.translate").reset()
  local resolved = config.setup(opts)
  cache.setup(resolved.max_cache_size)

  remove_mapping()
  if resolved.trigger_key then
    mapped_key = resolved.trigger_key
    vim.keymap.set({ "n", "x" }, mapped_key, M.translate, {
      desc = "Translate or look up text",
      silent = true,
    })
  end

  pcall(vim.api.nvim_del_user_command, "Translate")
  vim.api.nvim_create_user_command("Translate", M.translate, {
    desc = "Translate or look up the word under cursor",
  })
end

function M.translate()
  require("nvim-translate.translate").translate()
end

function M.cancel()
  require("nvim-translate.translate").cancel()
end

function M.focus()
  return require("nvim-translate.hover").focus()
end

function M.clear_cache()
  cache.clear()
  vim.notify("[nvim-translate] Cache cleared", vim.log.levels.INFO)
end

return M
