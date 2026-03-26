local M = {} -- Module (public)
local H = {} -- Helpers (private)

-- Panel state
H.win = nil
H.buf = nil
H.endpoints = {} -- parsed endpoints for the current panel
H.source_buf = nil -- the buffer we parsed endpoints from

--- Open the floating panel.
---@param source_buf number buffer to parse endpoints from
M.open = function(source_buf)
  if H.win and vim.api.nvim_win_is_valid(H.win) then
    return
  end

  H.source_buf = source_buf
  local parse = require('curls.parse')
  H.endpoints = parse.parse_buffer(H.source_buf)

  H.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[H.buf].bufhidden = 'wipe'

  local win_opts = H.win_config()
  H.win = vim.api.nvim_open_win(H.buf, true, win_opts)

  H.render_list()

  vim.wo[H.win].cursorline = true
  vim.wo[H.win].number = false
  vim.wo[H.win].relativenumber = false
  vim.wo[H.win].signcolumn = 'no'

  -- Close when the buffer is wiped
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = H.buf,
    once = true,
    callback = function()
      H.win = nil
      H.buf = nil
    end,
  })
end

--- Close the floating panel.
M.close = function()
  if H.win and vim.api.nvim_win_is_valid(H.win) then
    vim.api.nvim_win_close(H.win, true)
  end

  H.win = nil
  H.buf = nil
end

-- ============================================================================
-- Helpers
-- ============================================================================

--- Render the endpoint list into the panel buffer.
H.render_list = function()
  local lines = {}

  if #H.endpoints == 0 then
    table.insert(lines, '  No endpoints found')
  else
    for _, ep in ipairs(H.endpoints) do
      table.insert(lines, H.format_endpoint(ep))
    end
  end

  vim.bo[H.buf].modifiable = true
  vim.api.nvim_buf_set_lines(H.buf, 0, -1, false, lines)
  vim.bo[H.buf].modifiable = false

  -- Place cursor on first endpoint
  vim.api.nvim_win_set_cursor(H.win, { 1, 0 })
end

--- Format a single endpoint as a display line.
---@param ep table
---@return string
H.format_endpoint = function(ep)
  local method = string.format('%-6s', ep.method)
  local status = ep.last_status and string.format('[%d %dms]', ep.last_status, ep.last_time or 0) or '[—]'
  return string.format(' %s %s  %s', method, ep.path, status)
end

--- Build the float window config (80% of screen, centered).
---@return table
H.win_config = function()
  return {
    relative = 'editor',
    width = math.floor(vim.o.columns * 0.8),
    height = math.floor(vim.o.lines * 0.8),
    row = 0.1,
    col = 0.1,
    style = 'minimal',
    border = 'rounded',
    title = ' curls ',
    title_pos = 'center',
  }
end

return M
