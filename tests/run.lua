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
  equal(true, opts.stream)
  equal(160, opts.stream_update_interval)
  equal(84, opts.width)
  equal(28, opts.height)
  equal(" 再按 <leader>ut 进入 ", opts.footer)
  equal(" 翻译／词典 ", opts.title)
  assert(opts.prompt:find("## 发音与词形", 1, true))
  assert(opts.prompt:find("## 译文", 1, true))
  assert(opts.prompt:find("**原形**", 1, true))
  assert(opts.prompt:find("grammatically", 1, true))
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
    stream = true,
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
  equal(true, body.stream)
  equal(false, body.enable_thinking)
  local encoded_body = vim.json.decode(system_opts.stdin)
  equal(false, encoded_body.enable_thinking)
  equal(nil, encoded_body.extra_body)
  assert(vim.tbl_contains(args, "--no-buffer"))
  assert(vim.tbl_contains(args, "Accept: text/event-stream"))
  equal("https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", args[#args])
end)

test("streaming request parses SSE split across arbitrary chunks", function()
  local original_system = vim.system
  local captured_opts
  local deltas = {}
  local completed
  local completion_error

  local ok, err = xpcall(function()
    vim.system = function(_, system_opts, on_exit)
      captured_opts = system_opts
      if type(system_opts.stdout) == "function" then
        system_opts.stdout(nil, 'data: {"choices":[{"delta":{"cont')
        system_opts.stdout(nil, 'ent":"你"}}]}\n\ndata: {"choices":[{"delta":{"content":"好"}}]}\n\n')
        system_opts.stdout(nil, "data: [DONE]\n\n")
        system_opts.stdout(nil, nil)
        on_exit({ code = 0, signal = 0, stderr = "" })
      end
      return {
        is_closing = function()
          return false
        end,
      }
    end

    require("nvim-translate.llm").chat({
      api_key = "secret-token",
      base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1",
      model = "qwen3.7-flash",
      messages = { { role = "user", content = "hello" } },
      temperature = 0.2,
      max_tokens = 100,
      stream = true,
      extra_body = { enable_thinking = false },
      connect_timeout = 3,
      timeout = 5,
    }, function(result, request_error)
      completed = result
      completion_error = request_error
    end, function(delta)
      deltas[#deltas + 1] = delta
    end)

    equal("function", type(captured_opts and captured_opts.stdout))
    equal({ "你", "好" }, deltas)
    equal("你好", completed)
    equal(nil, completion_error)
  end, debug.traceback)

  vim.system = original_system
  assert(ok, err)
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
  equal("markdown", vim.bo[buf].filetype)
  local initial_width = vim.api.nvim_win_get_width(win)
  local initial_height = vim.api.nvim_win_get_height(win)
  local text_changes = 0
  vim.api.nvim_create_autocmd("TextChanged", {
    buffer = buf,
    callback = function()
      text_changes = text_changes + 1
    end,
  })
  local updated_line = "你好，世界：" .. string.rep("x", 30)
  hover.update({ updated_line })
  equal(updated_line, vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
  equal(1, text_changes)
  equal(initial_width, vim.api.nvim_win_get_width(win))
  equal(initial_height, vim.api.nvim_win_get_height(win))
  assert(vim.inspect(vim.api.nvim_win_get_config(win).footer):find("<leader>ut", 1, true))
  hover.focus()
  equal(win, vim.api.nvim_get_current_win())
  equal("", vim.fn.maparg("<C-d>", "n"))
  equal("", vim.fn.maparg("<C-u>", "n"))
  hover.close()
  equal(false, hover.is_open())
  equal(1, closes)
end)

test("streamed content appears with the source before completion", function()
  local callbacks = {}
  local chunk_callbacks = {}
  local displays = {}
  local open = false
  local on_close
  local focuses = 0

  package.loaded["nvim-translate.llm"] = {
    chat = function(_, callback, on_chunk)
      callbacks[#callbacks + 1] = callback
      chunk_callbacks[#chunk_callbacks + 1] = on_chunk
      return {
        is_closing = function()
          return false
        end,
        kill = function() end,
      }
    end,
  }
  package.loaded["nvim-translate.hover"] = {
    is_open = function()
      return open
    end,
    focus = function()
      focuses = focuses + 1
    end,
    show = function(value, opts)
      open = true
      on_close = opts.on_close
      displays[#displays + 1] = table.concat(value, "\n")
    end,
    update = function(value)
      displays[#displays + 1] = table.concat(value, "\n")
    end,
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
  config.setup({ api_key = "test", stream_update_interval = 1 })
  cache.setup(10)
  local translate = require("nvim-translate.translate")

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  translate.translate()
  assert(displays[1]:find("[!ABSTRACT] 词条", 1, true))
  assert(displays[1]:find("alpha", 1, true))
  equal("function", type(chunk_callbacks[1]))
  translate.translate()
  equal(1, focuses)
  equal(1, #callbacks)

  local initial_updates = #displays
  vim.wait(250)
  equal(initial_updates, #displays)

  chunk_callbacks[1]("## 发音")
  vim.wait(20)
  equal(initial_updates, #displays)

  chunk_callbacks[1]("与词形\n- **原形**")
  assert(vim.wait(100, function()
    return displays[#displays]:find("## 发音与词形", 1, true) ~= nil
  end))
  assert(not displays[#displays]:find("**原形**", 1, true))
  assert(displays[#displays]:find("alpha", 1, true))

  chunk_callbacks[1](" `alpha`\n")
  assert(vim.wait(100, function()
    return displays[#displays]:find("**原形** `alpha`", 1, true) ~= nil
  end))

  callbacks[1]("## 发音与词形\n- **原形** `alpha`\n完整结果", nil)
  assert(vim.wait(100, function()
    return displays[#displays]:find("完整结果", 1, true) ~= nil
  end))
  translate.cancel()

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
  vim.cmd("normal! gg0v$")
  translate.translate()
  assert(displays[#displays]:find("[!QUOTE] 原文", 1, true))
  assert(displays[#displays]:find("hello world", 1, true))
  translate.cancel()
  vim.cmd("normal! \27")
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
    update = function(value)
      displays[#displays + 1] = table.concat(value, "\n")
    end,
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
  config.setup({ api_key = "test" })
  cache.setup(10)
  local translate = require("nvim-translate.translate")

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "beta alpha" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  translate.translate()
  callbacks[1]("B", nil)
  local beta_display = "> [!ABSTRACT] 词条\n> **beta**\n\nB"
  vim.wait(100, function()
    return displays[#displays] == beta_display
  end)

  package.loaded["nvim-translate.hover"].close(true)
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  translate.translate()
  local alpha_callback = callbacks[2]
  package.loaded["nvim-translate.hover"].close(true)
  equal(1, kills)

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  translate.translate()
  equal(beta_display, displays[#displays])
  alpha_callback("A", nil)
  vim.wait(20)
  equal(beta_display, displays[#displays])
  translate.cancel()
end)

if failures > 0 then
  vim.cmd("cquit " .. failures)
end
vim.cmd("qa!")
