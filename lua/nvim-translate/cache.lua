local M = {}

local entries = {}
local capacity = 100
local directory = false
local write_sequence = 0
local last_used = 0

local function timestamp()
  local seconds, microseconds = vim.uv.gettimeofday()
  last_used = math.max(last_used + 1, seconds * 1000000 + microseconds)
  return last_used
end

local function filename(key)
  return directory .. "/" .. vim.fn.sha256(key) .. ".json"
end

local function read(path)
  local ok, content = pcall(vim.fn.readfile, path, "b")
  if not ok then
    return nil
  end
  local decoded, entry = pcall(vim.json.decode, table.concat(content, "\n"))
  if
    not decoded
    or type(entry) ~= "table"
    or entry.version ~= 1
    or type(entry.key) ~= "string"
    or type(entry.text) ~= "string"
    or type(entry.value) ~= "string"
    or (entry.mode ~= "dictionary" and entry.mode ~= "auto")
    or type(entry.is_word) ~= "boolean"
    or type(entry.created_at) ~= "number"
    or type(entry.used_at) ~= "number"
  then
    return nil
  end
  last_used = math.max(last_used, entry.used_at)
  return entry
end

local function files()
  local result = {}
  local scan = directory and vim.uv.fs_scandir(directory)
  if not scan then
    return result
  end
  while true do
    local name, kind = vim.uv.fs_scandir_next(scan)
    if not name then
      break
    end
    if kind == "file" and #name == 69 and name:match("^[0-9a-f]+%.json$") then
      result[#result + 1] = directory .. "/" .. name
    end
  end
  return result
end

local function refresh()
  if not directory then
    return
  end
  entries = {}
  for _, path in ipairs(files()) do
    local entry = read(path)
    if entry and path == filename(entry.key) then
      entries[entry.key] = entry
    end
  end
end

local function write(entry)
  if not directory then
    return true
  end
  local ok, err = pcall(vim.fn.mkdir, directory, "p", 448)
  if not ok then
    return false, tostring(err)
  end
  write_sequence = write_sequence + 1
  local path = filename(entry.key)
  local temporary = path .. "." .. vim.uv.os_getpid() .. "." .. write_sequence .. ".tmp"
  local encoded = vim.json.encode(entry)
  local written, result = pcall(vim.fn.writefile, { encoded }, temporary, "b")
  if not written or result ~= 0 then
    os.remove(temporary)
    return false, "Could not write cache: " .. tostring(result)
  end
  vim.uv.fs_chmod(temporary, 384)
  -- Independent entry files prevent writers in other Neovim processes from
  -- replacing an entire stale cache snapshot. Rename keeps each entry atomic.
  local renamed, rename_error = os.rename(temporary, path)
  if not renamed then
    os.remove(temporary)
    return false, tostring(rename_error)
  end
  return true
end

local function sorted()
  local result = vim.tbl_values(entries)
  table.sort(result, function(first, second)
    return first.used_at == second.used_at and first.key < second.key or first.used_at > second.used_at
  end)
  return result
end

local function prune()
  refresh()
  if capacity == 0 then
    return
  end
  local ordered = sorted()
  for index = capacity + 1, #ordered do
    local entry = ordered[index]
    if directory then
      os.remove(filename(entry.key))
    end
    entries[entry.key] = nil
  end
end

function M.setup(max_size, cache_dir)
  capacity = max_size or 100
  directory = cache_dir or false
  entries = {}
  last_used = 0
  prune()
end

function M.get_entry(key)
  if capacity == 0 then
    return nil
  end
  local entry
  if directory then
    entry = read(filename(key))
  else
    entry = entries[key]
  end
  if not entry or entry.key ~= key then
    entries[key] = nil
    return nil
  end
  entry.used_at = timestamp()
  entries[key] = entry
  write(entry)
  return vim.deepcopy(entry)
end

function M.get(key)
  local entry = M.get_entry(key)
  return entry and entry.value or nil
end

function M.set(key, value, metadata)
  if capacity == 0 then
    return false
  end
  refresh()
  metadata = metadata or {}
  local previous = entries[key]
  local time = timestamp()
  local entry = {
    version = 1,
    key = key,
    text = metadata.text or key,
    mode = metadata.mode or "auto",
    is_word = metadata.is_word == true,
    value = value,
    created_at = previous and previous.created_at or time,
    used_at = time,
  }
  local ok, err = write(entry)
  if not ok then
    return false, err
  end
  entries[key] = entry
  prune()
  return true
end

function M.history()
  if capacity == 0 then
    return {}
  end
  refresh()
  return vim.deepcopy(sorted())
end

function M.clear()
  for _, path in ipairs(files()) do
    local ok, err = os.remove(path)
    if not ok then
      return false, tostring(err)
    end
  end
  entries = {}
  last_used = 0
  return true
end

function M.size()
  return #M.history()
end

return M
