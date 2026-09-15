local config = require("nvim-translate.config")

local M = {}

local state = {
  win = nil,
  buf = nil,
  source_win = nil,
  source_buf = nil,
  anchor = nil,
  augroup = nil,
  on_close = nil,
  focusing = false,
}
local closing = false

local function window_size(value, total)
  if value <= 1 then
    return math.max(1, math.floor(total * value))
  end
  return math.floor(value)
end

local function content_size(lines)
  local cfg = config.get()
  local max_width = window_size(cfg.max_width, vim.o.columns)
  local max_height = window_size(cfg.max_height, vim.o.lines)
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width, max_width)

  local height = 0
  for _, line in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  return width, math.min(math.max(1, height), max_height)
end

local function resize(lines)
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local width, height = content_size(lines)
  local win_config = vim.api.nvim_win_get_config(state.win)
  win_config.width = width
  win_config.height = height
  vim.api.nvim_win_set_config(state.win, win_config)
end

local function contains(anchor, position)
  if not anchor then
    return true
  end
  local row, col = position[1], position[2]
  if row < anchor.start_row or row > anchor.end_row then
    return false
  end
  if row == anchor.start_row and col < anchor.start_col then
    return false
  end
  if row == anchor.end_row and col > anchor.end_col then
    return false
  end
  return true
end

local function close(notify)
  if closing then
    return
  end
  closing = true

  local win = state.win
  local callback = state.on_close
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  end

  state.win = nil
  state.buf = nil
  state.source_win = nil
  state.source_buf = nil
  state.anchor = nil
  state.augroup = nil
  state.on_close = nil
  state.focusing = false

  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  closing = false

  if notify and callback then
    callback()
  end
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.show(lines, opts)
  opts = opts or {}
  close(false)

  if not lines or #lines == 0 then
    lines = { "" }
  end

  local source_win = opts.source_win or vim.api.nvim_get_current_win()
  local source_buf = opts.source_buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_win_is_valid(source_win) or not vim.api.nvim_buf_is_valid(source_buf) then
    return nil, nil
  end

  local cfg = config.get()
  local buf
  local win
  vim.api.nvim_win_call(source_win, function()
    buf, win = vim.lsp.util.open_floating_preview(lines, "markdown", {
      border = cfg.border,
      close_events = {},
      focus = false,
      focusable = true,
      max_width = window_size(cfg.max_width, vim.o.columns),
      max_height = window_size(cfg.max_height, vim.o.lines),
      title = cfg.title,
      title_pos = "center",
      wrap = true,
    })
  end)
  vim.bo[buf].filetype = "markdown"

  state.win = win
  state.buf = buf
  state.source_win = source_win
  state.source_buf = source_buf
  state.anchor = opts.anchor
  state.on_close = opts.on_close
  state.augroup = vim.api.nvim_create_augroup("NvimTranslateHover", { clear = true })

  vim.keymap.set("n", "<Esc>", function()
    close(true)
  end, { buffer = buf, desc = "Close translation or dictionary", silent = true })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.augroup,
    pattern = tostring(win),
    once = true,
    callback = function()
      close(true)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.augroup,
    buffer = source_buf,
    callback = function()
      if state.focusing or vim.api.nvim_get_current_win() ~= source_win then
        return
      end
      if not contains(state.anchor, vim.api.nvim_win_get_cursor(source_win)) then
        close(true)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = state.augroup,
    buffer = source_buf,
    callback = function()
      if not state.focusing then
        close(true)
      end
    end,
  })

  return buf, win
end

function M.update(lines)
  if not M.is_open() or not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  resize(lines)
end

function M.focus()
  if not M.is_open() then
    return
  end
  state.focusing = true
  vim.api.nvim_set_current_win(state.win)
  state.focusing = false
end

function M.close(notify)
  close(notify ~= false)
end

return M
