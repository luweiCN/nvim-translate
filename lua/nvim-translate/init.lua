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
  cache.setup(resolved.max_cache_size, resolved.cache_dir)

  remove_mapping()
  if resolved.trigger_key then
    mapped_key = resolved.trigger_key
    vim.keymap.set({ "n", "x" }, mapped_key, M.translate, {
      desc = "Translate or look up text",
      silent = true,
    })
  end

  pcall(vim.api.nvim_del_user_command, "Translate")
  vim.api.nvim_create_user_command("Translate", function()
    M.translate()
  end, {
    desc = "Translate or look up the word under cursor",
  })
  pcall(vim.api.nvim_del_user_command, "TranslateInput")
  vim.api.nvim_create_user_command("TranslateInput", M.input, {
    desc = "Enter text to translate or look up",
  })
end

function M.translate(text)
  require("nvim-translate.translate").translate(text)
end

function M.input()
  M.cancel()
  vim.ui.input({ prompt = "翻译／查词： " }, function(text)
    if not text or not text:match("%S") then
      return
    end
    vim.schedule(function()
      vim.cmd.stopinsert()
      M.translate(vim.trim(text))
    end)
  end)
end

function M.history()
  return require("nvim-translate.translate").history()
end

function M.open_history(key)
  return require("nvim-translate.translate").open_history(key)
end

function M.cancel()
  require("nvim-translate.translate").cancel()
end

function M.focus()
  return require("nvim-translate.hover").focus()
end

function M.clear_cache()
  local ok, err = cache.clear()
  if not ok then
    vim.notify("[nvim-translate] Could not clear cache: " .. err, vim.log.levels.WARN)
    return
  end
  vim.notify("[nvim-translate] Cache cleared", vim.log.levels.INFO)
end

return M
