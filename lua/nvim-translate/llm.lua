local M = {}

local API_KEY_ENV = "NVIM_TRANSLATE_REQUEST_API_KEY"

local function endpoint(base_url)
  local value = base_url:gsub("/+$", "")
  if not value:match("^https?://") then
    error("base_url must start with http:// or https://")
  end
  if value:match("/chat/completions$") then
    return value
  end
  return value .. "/chat/completions"
end

local function redact(value, secret)
  value = tostring(value or "")
  if secret == "" then
    return value
  end
  local escaped = secret:gsub("([^%w])", "%%%1")
  return value:gsub(escaped, "[REDACTED]")
end

local function response_error(stdout)
  if not stdout or stdout == "" then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, stdout)
  if not ok or type(decoded) ~= "table" or decoded.error == nil then
    return nil
  end
  if type(decoded.error) == "table" then
    return decoded.error.message or decoded.error.code
  end
  return tostring(decoded.error)
end

local function response_content(decoded)
  return decoded.choices and decoded.choices[1] and decoded.choices[1].message and decoded.choices[1].message.content
end

local function stream_parser(on_chunk)
  local pending = ""
  local parts = {}
  local stream_error

  local function parse_line(line)
    local payload = line:gsub("\r$", ""):match("^data:%s*(.+)$")
    if not payload or payload == "[DONE]" or stream_error then
      return
    end

    local ok, event = pcall(vim.json.decode, payload)
    if not ok then
      stream_error = "failed to parse streaming API response: " .. tostring(event)
      return
    end
    if event.error ~= nil then
      if type(event.error) == "table" then
        stream_error = event.error.message or event.error.code or vim.inspect(event.error)
      else
        stream_error = tostring(event.error)
      end
      return
    end

    local delta = event.choices and event.choices[1] and event.choices[1].delta
    local content = delta and delta.content
    if type(content) ~= "string" or content == "" then
      return
    end
    parts[#parts + 1] = content
    if on_chunk then
      local callback_ok, callback_error = pcall(on_chunk, content)
      if not callback_ok then
        stream_error = "stream callback failed: " .. tostring(callback_error)
      end
    end
  end

  local function feed(data)
    if not data or data == "" then
      return
    end
    pending = pending .. data
    while true do
      local newline = pending:find("\n", 1, true)
      if not newline then
        return
      end
      parse_line(pending:sub(1, newline - 1))
      pending = pending:sub(newline + 1)
    end
  end

  local function finish()
    if pending ~= "" then
      parse_line(pending)
      pending = ""
    end
    return table.concat(parts), stream_error
  end

  return feed, finish
end

function M.build(opts)
  local body = vim.deepcopy(opts.extra_body or {})
  body.model = opts.model
  body.messages = vim.deepcopy(opts.messages)
  body.temperature = opts.temperature
  body.max_tokens = opts.max_tokens
  body.stream = opts.stream == true
  local encoded = vim.json.encode(body)
  local accept = body.stream and "text/event-stream" or "application/json"
  local args = {
    "curl",
    "--disable",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--connect-timeout",
    tostring(opts.connect_timeout),
    "--max-time",
    tostring(opts.timeout),
    "--request",
    "POST",
    "--header",
    "Content-Type: application/json",
    "--header",
    "Accept: " .. accept,
    "--variable",
    "%" .. API_KEY_ENV,
    "--expand-header",
    "Authorization: Bearer {{" .. API_KEY_ENV .. "}}",
  }
  if body.stream then
    args[#args + 1] = "--no-buffer"
  end
  args[#args + 1] = "--data-binary"
  args[#args + 1] = "@-"
  args[#args + 1] = endpoint(opts.base_url)
  local system_opts = {
    text = true,
    stdin = encoded,
    env = { [API_KEY_ENV] = opts.api_key },
  }
  return args, system_opts, body
end

function M.chat(opts, on_complete, on_chunk)
  if vim.fn.executable("curl") ~= 1 then
    vim.schedule(function()
      on_complete(nil, "curl is not available in PATH")
    end)
    return nil
  end

  local ok, args, system_opts = pcall(M.build, opts)
  if not ok then
    vim.schedule(function()
      on_complete(nil, redact(args, opts.api_key))
    end)
    return nil
  end

  local raw = {}
  local stdout_error
  local finish_stream
  if opts.stream then
    local feed_stream
    feed_stream, finish_stream = stream_parser(on_chunk)
    system_opts.stdout = function(err, data)
      if err then
        stdout_error = err
      end
      if data then
        raw[#raw + 1] = data
        feed_stream(data)
      end
    end
  end

  local started, process = pcall(vim.system, args, system_opts, function(result)
    local stdout = opts.stream and table.concat(raw) or result.stdout
    local api_error = response_error(stdout)
    if result.code ~= 0 then
      local message = api_error or vim.trim(result.stderr or "")
      if message == "" then
        message = "curl exited with code " .. result.code
      end
      on_complete(nil, redact(message, opts.api_key))
      return
    end

    if stdout_error then
      on_complete(nil, "failed to read streaming API response: " .. redact(stdout_error, opts.api_key))
      return
    end
    if api_error then
      on_complete(nil, redact(api_error, opts.api_key))
      return
    end

    if finish_stream then
      local content, stream_error = finish_stream()
      if stream_error then
        on_complete(nil, redact(stream_error, opts.api_key))
      elseif content == "" then
        on_complete(nil, "API response did not contain message content")
      else
        on_complete(content, nil)
      end
      return
    end

    local decoded_ok, decoded = pcall(vim.json.decode, stdout or "")
    if not decoded_ok then
      on_complete(nil, "failed to parse API response: " .. redact(decoded, opts.api_key))
      return
    end
    local content = response_content(decoded)
    if type(content) ~= "string" or content == "" then
      on_complete(nil, "API response did not contain message content")
      return
    end
    on_complete(content, nil)
  end)

  if not started then
    vim.schedule(function()
      on_complete(nil, redact(process, opts.api_key))
    end)
    return nil
  end
  return process
end

return M
