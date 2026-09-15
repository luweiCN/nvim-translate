local failures = 0

local function test(name, callback)
  local ok, err = xpcall(callback, debug.traceback)
  if ok then
    print("ok - " .. name)
    return
  end
  failures = failures + 1
  print("not ok - " .. name .. "\n" .. err)
end

local function equal(expected, actual)
  assert(vim.deep_equal(expected, actual), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

test("Qwen defaults are internally consistent", function()
  local config = require("nvim-translate.config")
  local opts = config.setup()
  equal("https://dashscope.aliyuncs.com/compatible-mode/v1", config.resolve_base_url())
  equal("qwen3.7-flash", opts.model)
  equal({ enable_thinking = false }, opts.extra_body)
  assert(opts.prompt:find("**词条**", 1, true))
  assert(opts.prompt:find("**翻译**", 1, true))
  equal(false, opts.trigger_key)
end)

test("provider-specific body can be cleared", function()
  local config = require("nvim-translate.config")
  equal({}, config.setup({ extra_body = {} }).extra_body)
end)

test("cache evicts the least recently used entry", function()
  local cache = require("nvim-translate.cache")
  cache.setup(2)
  cache.set("a", "A")
  cache.set("b", "B")
  equal("A", cache.get("a"))
  cache.set("c", "C")
  equal(nil, cache.get("b"))
  equal("A", cache.get("a"))
  equal("C", cache.get("c"))
  equal(2, cache.size())
end)

test("request keeps the key and source text out of argv", function()
  local llm = require("nvim-translate.llm")
  local source = "private selected text"
  local secret = "secret-token"
  local args, system_opts, body = llm.build({
    api_key = secret,
    base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/",
    model = "qwen3.7-flash",
    messages = { { role = "user", content = source } },
    temperature = 0.2,
    max_tokens = 100,
    extra_body = { model = "must-not-win", stream = true, enable_thinking = false },
    connect_timeout = 3,
    timeout = 5,
  })
  local argv = table.concat(args, "\n")
  assert(not argv:find(secret, 1, true))
  assert(not argv:find(source, 1, true))
  assert(system_opts.stdin:find(source, 1, true))
  equal(secret, system_opts.env.NVIM_TRANSLATE_REQUEST_API_KEY)
  equal("qwen3.7-flash", body.model)
  equal(false, body.stream)
  equal(false, body.enable_thinking)
  local encoded_body = vim.json.decode(system_opts.stdin)
  equal(false, encoded_body.enable_thinking)
  equal(nil, encoded_body.extra_body)
  equal("https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", args[#args])
end)

test("setup does not create a mapping unless requested", function()
  local plugin = require("nvim-translate")
  plugin.setup({ trigger_key = false })
  equal("", vim.fn.maparg("<leader>xx", "n"))
  equal(2, vim.fn.exists(":Translate"))
end)

test("hover can be updated, focused, and closed once", function()
  local config = require("nvim-translate.config")
  config.setup()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })

  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_get_current_buf()
  local closes = 0
  local hover = require("nvim-translate.hover")
  local buf, win = hover.show({ "你好" }, {
    source_win = source_win,
    source_buf = source_buf,
    anchor = { start_row = 1, end_row = 1, start_col = 0, end_col = 4 },
    on_close = function()
      closes = closes + 1
    end,
  })

  assert(vim.api.nvim_win_is_valid(win))
  hover.update({ "你好，世界" })
  equal("你好，世界", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
  hover.focus()
  equal(win, vim.api.nvim_get_current_win())
  hover.close()
  equal(false, hover.is_open())
  equal(1, closes)
end)

test("a cached result invalidates an older pending response", function()
  local callbacks = {}
  local displays = {}
  local open = false
  local on_close
  local kills = 0

  package.loaded["nvim-translate.llm"] = {
    chat = function(_, callback)
      callbacks[#callbacks + 1] = callback
      return {
        is_closing = function()
          return false
        end,
        kill = function()
          kills = kills + 1
        end,
      }
    end,
  }
  package.loaded["nvim-translate.hover"] = {
    is_open = function()
      return open
    end,
    focus = function() end,
    show = function(value, opts)
      open = true
      on_close = opts.on_close
      displays[#displays + 1] = table.concat(value, "\n")
    end,
    update = function() end,
    close = function(notify)
      open = false
      if notify ~= false and on_close then
        on_close()
      end
    end,
  }
  package.loaded["nvim-translate.translate"] = nil

  local config = require("nvim-translate.config")
  local cache = require("nvim-translate.cache")
  config.setup({ api_key = "test", spinner_interval = 100000 })
  cache.setup(10)
  local translate = require("nvim-translate.translate")

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "beta alpha" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  translate.translate()
  callbacks[1]("B", nil)
  vim.wait(100, function()
    return displays[#displays] == "B"
  end)

  package.loaded["nvim-translate.hover"].close(true)
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  translate.translate()
  local alpha_callback = callbacks[2]
  package.loaded["nvim-translate.hover"].close(true)
  equal(1, kills)

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  translate.translate()
  equal("B", displays[#displays])
  alpha_callback("A", nil)
  vim.wait(20)
  equal("B", displays[#displays])
  translate.cancel()
end)

if failures > 0 then
  vim.cmd("cquit " .. failures)
end
vim.cmd("qa!")
