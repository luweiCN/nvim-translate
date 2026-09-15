local M = {}

local entries = {}
local clock = 0
local size = 0
local capacity = 100

function M.setup(max_size)
  capacity = max_size or 100
  entries = {}
  clock = 0
  size = 0
end

function M.get(key)
  local entry = entries[key]
  if not entry then
    return nil
  end

  clock = clock + 1
  entry.used_at = clock
  return entry.value
end

function M.set(key, value)
  if capacity == 0 then
    return
  end

  local entry = entries[key]
  if entry then
    clock = clock + 1
    entry.value = value
    entry.used_at = clock
    return
  end

  if size >= capacity then
    local oldest_key
    local oldest_time = math.huge
    for candidate, item in pairs(entries) do
      if item.used_at < oldest_time then
        oldest_key = candidate
        oldest_time = item.used_at
      end
    end
    if oldest_key then
      entries[oldest_key] = nil
      size = size - 1
    end
  end

  clock = clock + 1
  entries[key] = { value = value, used_at = clock }
  size = size + 1
end

function M.clear()
  entries = {}
  clock = 0
  size = 0
end

function M.size()
  return size
end

return M
