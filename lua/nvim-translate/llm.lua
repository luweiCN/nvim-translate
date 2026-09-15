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

function M.build(opts)
  local body = vim.deepcopy(opts.extra_body or {})
  body.model = opts.model
  body.messages = vim.deepcopy(opts.messages)
  body.temperature = opts.temperature
  body.max_tokens = opts.max_tokens
  body.stream = false
  local encoded = vim.json.encode(body)
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
    "Accept: application/json",
    "--variable",
    "%" .. API_KEY_ENV,
    "--expand-header",
    "Authorization: Bearer {{" .. API_KEY_ENV .. "}}",
    "--data-binary",
    "@-",
    endpoint(opts.base_url),
  }
  local system_opts = {
    text = true,
    stdin = encoded,
    env = { [API_KEY_ENV] = opts.api_key },
  }
  return args, system_opts, body
end

function M.chat(opts, on_complete)
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

  local started, process = pcall(vim.system, args, system_opts, function(result)
    local api_error = response_error(result.stdout)
    if result.code ~= 0 then
      local message = api_error or vim.trim(result.stderr or "")
      if message == "" then
        message = "curl exited with code " .. result.code
      end
      on_complete(nil, redact(message, opts.api_key))
      return
    end

    local decoded_ok, decoded = pcall(vim.json.decode, result.stdout or "")
    if not decoded_ok then
      on_complete(nil, "failed to parse API response: " .. redact(decoded, opts.api_key))
      return
    end
    if api_error then
      on_complete(nil, redact(api_error, opts.api_key))
      return
    end

    local content = decoded.choices
      and decoded.choices[1]
      and decoded.choices[1].message
      and decoded.choices[1].message.content
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
