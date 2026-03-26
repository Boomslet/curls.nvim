local M = {} -- Module (public)
local H = {} -- Helpers (private)

H.WIDTH = 0.8
H.BODY_METHODS = { POST = true, PUT = true, PATCH = true }

H.win = nil
H.buf = nil
H.endpoints = {}
H.source_buf = nil
H.list_len = 0
H.prev_row = nil

---@param source_buf number buffer to parse endpoints from
M.open = function(source_buf)
  if H.win and vim.api.nvim_win_is_valid(H.win) then
    return
  end

  H.source_buf = source_buf
  H.endpoints = require('curls.parse').parse_buffer(H.source_buf)

  H.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[H.buf].bufhidden = 'wipe'

  H.win = vim.api.nvim_open_win(H.buf, true, H.win_config())

  H.render_list()

  vim.wo[H.win].cursorline = true
  vim.wo[H.win].number = false
  vim.wo[H.win].relativenumber = false
  vim.wo[H.win].signcolumn = 'no'

  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = H.buf,
    callback = function()
      local row = vim.api.nvim_win_get_cursor(H.win)[1]

      if row <= H.list_len and row ~= H.prev_row then
        H.prev_row = row
        H.render_detail()
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = H.buf,
    once = true,
    callback = H.reset,
  })
end

-- ============================================================================
-- Helpers
-- ============================================================================

H.reset = function()
  H.win = nil
  H.buf = nil
  H.endpoints = {}
  H.source_buf = nil
  H.list_len = 0
  H.prev_row = nil
end

H.panel_width = function()
  return math.floor(vim.o.columns * H.WIDTH)
end

H.render_list = function()
  local lines = {}

  if #H.endpoints == 0 then
    table.insert(lines, '  No endpoints found')
  else
    for _, ep in ipairs(H.endpoints) do
      table.insert(lines, H.format_endpoint(ep))
    end
  end

  H.list_len = #lines

  vim.bo[H.buf].modifiable = true
  vim.api.nvim_buf_set_lines(H.buf, 0, -1, false, lines)
  vim.bo[H.buf].modifiable = false

  vim.api.nvim_win_set_cursor(H.win, { 1, 0 })
  H.prev_row = 1
  H.render_detail()
end

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

H.render_detail = function()
  local endpoint = H.endpoints[H.prev_row]

  if not endpoint then return end

  local sep = string.rep('─', H.panel_width() - 2)
  local detail = vim.list_extend({ '', sep, '' }, H.build_curl(endpoint))

  if endpoint.last_response then
    table.insert(detail, '')
    table.insert(detail, '  ' .. H.format_status(endpoint))
    table.insert(detail, '')
    vim.list_extend(detail, vim.tbl_map(function(l) return '  ' .. l end, vim.split(endpoint.last_response, '\n')))
  end

  vim.bo[H.buf].modifiable = true
  vim.api.nvim_buf_set_lines(H.buf, H.list_len, -1, false, detail)
  vim.bo[H.buf].modifiable = false
end

---@param ep table
---@return string[]
H.build_curl = function(ep)
  local url = require('curls.init').state.base_url .. ep.path

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

---@return table
H.win_config = function()
  local width = H.panel_width()
  local height = math.floor(vim.o.lines * H.WIDTH)

  return {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' curls ',
    title_pos = 'center',
  }
end

return M
