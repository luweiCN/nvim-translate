local cache = require("nvim-translate.cache")
local config = require("nvim-translate.config")
local hover = require("nvim-translate.hover")
local llm = require("nvim-translate.llm")

local M = {}

local generation = 0
local process
local spinner

local function stop_spinner()
  if not spinner then
    return
  end
  spinner:stop()
  if not spinner:is_closing() then
    spinner:close()
  end
  spinner = nil
end

local function stop_process()
  if not process then
    return
  end
  if not process:is_closing() then
    pcall(process.kill, process, "sigterm")
  end
  process = nil
end

local function invalidate()
  generation = generation + 1
  stop_spinner()
  stop_process()
  return generation
end

local function word_anchor(word)
  local position = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local from = 1
  while true do
    local start_col, end_col = line:find(word, from, true)
    if not start_col then
      break
    end
    local start_zero = start_col - 1
    local end_zero = end_col - 1
    if position[2] >= start_zero and position[2] <= end_zero then
      return {
        start_row = position[1],
        end_row = position[1],
        start_col = start_zero,
        end_col = end_zero,
      }
    end
    from = end_col + 1
  end
  return {
    start_row = position[1],
    end_row = position[1],
    start_col = position[2],
    end_col = position[2],
  }
end

local function visual_anchor(first, last, mode)
  if first[2] > last[2] or (first[2] == last[2] and first[3] > last[3]) then
    first, last = last, first
  end
  return {
    start_row = first[2],
    end_row = last[2],
    start_col = mode == "V" and 0 or math.max(0, first[3] - 1),
    end_col = mode == "V" and math.huge or math.max(0, last[3] - 1),
  }
end

local function input()
  local mode = vim.fn.mode()
  if mode:match("^[vV\22]") then
    local first = vim.fn.getpos("v")
    local last = vim.fn.getpos(".")
    local lines = vim.fn.getregion(first, last, { type = mode })
    return table.concat(lines, "\n"), visual_anchor(first, last, mode)
  end

  local word = vim.fn.expand("<cword>")
  return word, word ~= "" and word_anchor(word) or nil
end

local function cache_key(opts, base_url, text)
  local values = {
    base_url,
    opts.model,
    opts.prompt,
    tostring(opts.temperature),
    tostring(opts.max_tokens),
    vim.json.encode(opts.extra_body),
    text,
  }
  local encoded = {}
  for index, value in ipairs(values) do
    encoded[index] = #value .. ":" .. value
  end
  return vim.fn.sha256(table.concat(encoded))
end

local function lines(value)
  return vim.split(value, "\n", { plain = true })
end

local function start_spinner(id)
  local opts = config.get()
  local frame = 1
  spinner = vim.uv.new_timer()
  spinner:start(
    0,
    opts.spinner_interval,
    vim.schedule_wrap(function()
      if id ~= generation or not hover.is_open() then
        stop_spinner()
        return
      end
      hover.update({ ("  %s  Translating..."):format(opts.spinner_frames[frame]) })
      frame = frame % #opts.spinner_frames + 1
    end)
  )
end

function M.translate()
  if hover.is_open() then
    hover.focus()
    return
  end

  local text, anchor = input()
  if not text or not text:match("%S") then
    vim.notify("[nvim-translate] Nothing to translate", vim.log.levels.WARN)
    return
  end

  local id = invalidate()
  local opts = config.get()
  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_get_current_buf()
  local base_url = config.resolve_base_url()
  local key = cache_key(opts, base_url, text)
  local hover_opts = {
    source_win = source_win,
    source_buf = source_buf,
    anchor = anchor,
    on_close = function()
      if id == generation then
        invalidate()
      end
    end,
  }

  if opts.cache_enabled then
    local cached = cache.get(key)
    if cached then
      hover.show(lines(cached), hover_opts)
      return
    end
  end

  local api_key, key_error = config.resolve_api_key()
  if not api_key then
    hover.show(lines("[Error] " .. key_error), hover_opts)
    return
  end

  hover.show({ "  |  Translating..." }, hover_opts)
  start_spinner(id)

  local current_process = llm.chat({
    api_key = api_key,
    base_url = base_url,
    model = opts.model,
    messages = {
      { role = "system", content = opts.prompt },
      { role = "user", content = text },
    },
    temperature = opts.temperature,
    max_tokens = opts.max_tokens,
    extra_body = opts.extra_body,
    connect_timeout = opts.connect_timeout,
    timeout = opts.timeout,
  }, function(result, request_error)
    vim.schedule(function()
      if id ~= generation then
        return
      end
      process = nil
      stop_spinner()
      if not hover.is_open() then
        return
      end
      if request_error then
        hover.show(lines("[Error] " .. request_error), hover_opts)
        return
      end
      if opts.cache_enabled then
        cache.set(key, result)
      end
      hover.show(lines(result), hover_opts)
    end)
  end)

  if id == generation then
    process = current_process
  elseif current_process and not current_process:is_closing() then
    pcall(current_process.kill, current_process, "sigterm")
  end
end

function M.cancel()
  invalidate()
  hover.close(false)
end

function M.reset()
  M.cancel()
end

return M
