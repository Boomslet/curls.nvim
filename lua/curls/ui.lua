local M = {} -- Module (public)
local H = {} -- Helpers (private)

H.BODY_METHODS = { POST = true, PUT = true, PATCH = true }

-- State for the current panel session
H.list_win = nil
H.list_buf = nil
H.detail_win = nil
H.detail_buf = nil
H.endpoints = {}
H.base_url = nil
H.prev_row = nil

-- ============================================================================
-- Public
-- ============================================================================

---@param source_buf number buffer to parse endpoints from
---@param base_url string
M.open = function(source_buf, base_url)
  if H.list_win and vim.api.nvim_win_is_valid(H.list_win) then
    return
  end

  H.base_url = base_url
  H.endpoints = require('curls.parse').parse_buffer(source_buf)

  H.create_windows()
  H.setup_keymaps()
  H.setup_autocmds()

  H.render_list()
  H.render_detail()
end

-- ============================================================================
-- Windows
-- ============================================================================

H.create_windows = function()
  local width = math.floor(vim.o.columns * 0.8)
  local total_height = math.floor(vim.o.lines * 0.8)
  local top = math.floor((vim.o.lines - total_height) / 2)
  local left = math.floor((vim.o.columns - width) / 2)
  local max_list = math.floor(total_height * 0.4)
  local list_height = math.min(math.max(#H.endpoints, 1), max_list)
  local detail_height = total_height - list_height - 2

  local base = {
    relative = 'editor',
    width = width,
    col = left,
    style = 'minimal',
    border = 'rounded',
  }

  H.list_buf = H.create_scratch_buf()
  H.list_win = vim.api.nvim_open_win(H.list_buf, true, vim.tbl_extend('force', base, {
    height = list_height,
    row = top,
    title = ' curls ',
    title_pos = 'center',
  }))

  H.detail_buf = H.create_scratch_buf()
  H.detail_win = vim.api.nvim_open_win(H.detail_buf, false, vim.tbl_extend('force', base, {
    height = detail_height,
    row = top + list_height + 2,
  }))

  H.set_win_opts(H.list_win, { cursorline = true })
  H.set_win_opts(H.detail_win, {})
end

H.create_scratch_buf = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  return buf
end

H.set_win_opts = function(win, extra)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  for k, v in pairs(extra) do
    vim.wo[win][k] = v
  end
end

-- ============================================================================
-- Keymaps
-- ============================================================================

H.setup_keymaps = function()
  -- List: 'i' enters edit mode in the detail window
  vim.keymap.set('n', 'i', function()
    if #H.endpoints == 0 then return end
    vim.bo[H.detail_buf].modifiable = true
    vim.api.nvim_set_current_win(H.detail_win)
  end, { buffer = H.list_buf, nowait = true })

  -- Detail: '<Esc>' returns to the list
  vim.keymap.set('n', '<Esc>', function()
    vim.bo[H.detail_buf].modifiable = false
    vim.api.nvim_set_current_win(H.list_win)
  end, { buffer = H.detail_buf, nowait = true })
end

-- ============================================================================
-- Autocmds
-- ============================================================================

H.setup_autocmds = function()
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = H.list_buf,
    callback = function()
      local row = vim.api.nvim_win_get_cursor(H.list_win)[1]
      if row ~= H.prev_row then
        H.prev_row = row
        H.render_detail()
      end
    end,
  })

  -- Clean up if either buffer is closed
  for _, buf in ipairs({ H.list_buf, H.detail_buf }) do
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      once = true,
      callback = H.reset,
    })
  end
end

-- ============================================================================
-- Rendering
-- ============================================================================

H.render_list = function()
  local lines = {}

  if #H.endpoints == 0 then
    lines = { '  No endpoints found' }
  else
    for _, ep in ipairs(H.endpoints) do
      table.insert(lines, H.format_endpoint(ep))
    end
  end

  H.set_lines(H.list_buf, lines)
  vim.api.nvim_win_set_cursor(H.list_win, { 1, 0 })
  H.prev_row = 1
end

H.render_detail = function()
  local ep = H.endpoints[H.prev_row]
  if not ep then return end

  local lines = H.build_curl(ep)

  if ep.last_response then
    table.insert(lines, '')
    table.insert(lines, '  ' .. H.format_status(ep))
    table.insert(lines, '')
    vim.list_extend(lines, vim.tbl_map(function(l) return '  ' .. l end, vim.split(ep.last_response, '\n')))
  end

  H.set_lines(H.detail_buf, lines)
end

-- ============================================================================
-- Formatting
-- ============================================================================

---@param ep table
---@return string
H.format_endpoint = function(ep)
  local method = string.format('%-6s', ep.method)
  local status = ep.last_status and H.format_status(ep) or '[—]'
  return string.format(' %s %s  %s', method, ep.path, status)
end

---@param ep table
---@return string
H.format_status = function(ep)
  return string.format('[%d %dms]', ep.last_status, ep.last_time or 0)
end

---@param ep table
---@return string[]
H.build_curl = function(ep)
  local url = H.base_url .. ep.path

  for _, param in ipairs(ep.path_params or {}) do
    url = url:gsub(':' .. param, '{' .. param .. '}')
  end

  local parts = { ('  curl -s -X %s \\'):format(ep.method) }

  if H.BODY_METHODS[ep.method] then
    table.insert(parts, "    -H 'Content-Type: application/json' \\")
    table.insert(parts, "    -d '{}' \\")
  end

  table.insert(parts, ("    '%s'"):format(url))

  return parts
end

-- ============================================================================
-- Utilities
-- ============================================================================

H.set_lines = function(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

H.reset = function()
  if H.detail_win and vim.api.nvim_win_is_valid(H.detail_win) then
    vim.api.nvim_win_close(H.detail_win, true)
  end
  H.list_win = nil
  H.list_buf = nil
  H.detail_win = nil
  H.detail_buf = nil
  H.endpoints = {}
  H.base_url = nil
  H.prev_row = nil
end

return M
