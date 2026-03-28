local M = {} -- Module (public)
local H = {} -- Helpers (private)

H.NS = vim.api.nvim_create_namespace('curls')
H.highlights_set = false

H.STATUS_TEXT = {
  [200] = 'OK', [201] = 'Created', [204] = 'No Content',
  [301] = 'Moved', [302] = 'Found', [304] = 'Not Modified',
  [400] = 'Bad Request', [401] = 'Unauthorized', [403] = 'Forbidden',
  [404] = 'Not Found', [405] = 'Method Not Allowed', [409] = 'Conflict',
  [422] = 'Unprocessable', [429] = 'Too Many Requests',
  [500] = 'Internal Server Error', [502] = 'Bad Gateway', [503] = 'Service Unavailable',
}

-- State for the current panel session
H.list_win = nil
H.list_buf = nil
H.detail_win = nil
H.detail_buf = nil
H.endpoints = {}
H.base_url = nil
H.on_close = nil
H.prev_row = nil
H.help_visible = false

-- ============================================================================
-- Public
-- ============================================================================

---@param source_buf number buffer to parse endpoints from
---@param opts { base_url: string, saved_curls?: table<string, string[]>, on_close?: function }
M.open = function(source_buf, opts)
  if H.list_win and vim.api.nvim_win_is_valid(H.list_win) then
    return
  end

  H.base_url = opts.base_url
  H.on_close = opts.on_close
  H.endpoints = require('curls.parse').parse_buffer(source_buf)

  -- Restore persisted curl edits
  if opts.saved_curls then
    local store = require('curls.store')
    for _, ep in ipairs(H.endpoints) do
      local key = store.endpoint_key(ep)
      if opts.saved_curls[key] then
        ep.edited_curl = opts.saved_curls[key]
      end
    end
  end

  H.create_windows()
  H.setup_keymaps()
  H.setup_autocmds()

  H.render_list()
  H.render_detail()
  H.render_help()
end

-- ============================================================================
-- Windows
-- ============================================================================

H.create_windows = function()
  H.setup_highlights()

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

  H.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[H.list_buf].bufhidden = 'wipe'
  H.list_win = vim.api.nvim_open_win(H.list_buf, true, vim.tbl_extend('force', base, {
    height = list_height,
    row = top,
    title = ' curls ',
    title_pos = 'center',
  }))

  H.detail_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[H.detail_buf].bufhidden = 'wipe'
  H.detail_win = vim.api.nvim_open_win(H.detail_buf, false, vim.tbl_extend('force', base, {
    height = detail_height,
    row = top + list_height + 2,
  }))

  for _, win in ipairs({ H.list_win, H.detail_win }) do
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = 'no'
  end
  vim.wo[H.list_win].cursorline = true
end

-- ============================================================================
-- Keymaps
-- ============================================================================

H.setup_keymaps = function()
  vim.keymap.set('n', '<CR>', function()
    if #H.endpoints == 0 then return end
    vim.bo[H.detail_buf].modifiable = true
    vim.api.nvim_set_current_win(H.detail_win)
  end, { buffer = H.list_buf, nowait = true })

  -- List: '<Space>' fires the curl
  vim.keymap.set('n', '<Space>', function()
    if #H.endpoints == 0 then return end
    H.execute_curl()
  end, { buffer = H.list_buf, nowait = true })

  -- List: 'u' changes the base URL
  vim.keymap.set('n', 'u', function()
    vim.ui.input({ prompt = 'Base URL: ', default = H.base_url }, function(input)
      if not input or input == '' then return end
      H.base_url = input:gsub('/$', '')
      H.render_detail()
    end)
  end, { buffer = H.list_buf, nowait = true })

  -- List: '?' toggles help line
  vim.keymap.set('n', '?', function()
    H.help_visible = not H.help_visible
    H.render_help()
  end, { buffer = H.list_buf, nowait = true })

  -- Detail: '<Esc>' returns to the list
  vim.keymap.set('n', '<Esc>', function()
    -- Save user's curl edits before locking the buffer
    local ep = H.endpoints[H.prev_row]
    if ep then
      local buf_lines = vim.api.nvim_buf_get_lines(H.detail_buf, 0, -1, false)
      local curl_lines = {}
      for _, line in ipairs(buf_lines) do
        if vim.trim(line) == '' then break end
        table.insert(curl_lines, line)
      end
      ep.edited_curl = curl_lines
    end
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

  -- Close both windows if focus leaves either one (ctrl+w, :q on detail, etc.)
  for _, buf in ipairs({ H.list_buf, H.detail_buf }) do
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      once = true,
      callback = H.reset,
    })

    vim.api.nvim_create_autocmd('WinLeave', {
      buffer = buf,
      callback = function()
        -- Allow switching between the two panel windows
        vim.schedule(function()
          local cur_win = vim.api.nvim_get_current_win()
          if cur_win ~= H.list_win and cur_win ~= H.detail_win then
            H.reset()
          end
        end)
      end,
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
  H.highlight_methods()
  vim.api.nvim_win_set_cursor(H.list_win, { 1, 0 })
  H.prev_row = 1
end

H.render_help = function()
  if not H.list_win or not vim.api.nvim_win_is_valid(H.list_win) then return end

  local footer
  if H.help_visible then
    footer = ' Enter:edit  Space:fire  u:base url  ?:close help '
  else
    footer = ' ? for help '
  end

  vim.api.nvim_win_set_config(H.list_win, { footer = footer, footer_pos = 'right' })
end

H.render_detail = function()
  local ep = H.endpoints[H.prev_row]
  if not ep then return end

  -- Use saved curl lines if the user has edited them, otherwise generate fresh
  local curl = require('curls.curl')
  local curl_lines = ep.edited_curl or curl.build(ep, H.base_url)
  local curl_line_count = #curl_lines

  local lines = vim.list_extend({}, curl_lines)

  if ep.last_response then
    table.insert(lines, '')
    table.insert(lines, H.format_status_detail(ep))
    table.insert(lines, '')
    vim.list_extend(lines, vim.tbl_map(function(l) return '  ' .. l end, vim.split(ep.last_response, '\n')))
  end

  H.set_lines(H.detail_buf, lines)

  if ep.last_response then
    H.highlight_status(ep.last_status, curl_line_count + 1)
  end
end

-- ============================================================================
-- Formatting
-- ============================================================================

---@param ep table
---@return string
H.METHOD_COL_START = 1  -- after leading space
H.METHOD_COL_END = 7    -- 6-char padded method

H.format_endpoint = function(ep)
  return string.format(' %-6s %s', ep.method, ep.path)
end

---@param ep table
---@return string
H.format_status_detail = function(ep)
  local text = H.STATUS_TEXT[ep.last_status] or ''
  local size = ep.last_response and #ep.last_response or 0
  return string.format('  %d %s  %dms  %d bytes', ep.last_status, text, ep.last_time or 0, size)
end

-- ============================================================================
-- Execution
-- ============================================================================

H.execute_curl = function()
  local ep = H.endpoints[H.prev_row]
  if not ep then return end

  -- Read the curl from the detail buffer (respects user edits)
  local detail_lines = vim.api.nvim_buf_get_lines(H.detail_buf, 0, -1, false)
  local curl = require('curls.curl')
  local args = curl.parse_args(detail_lines)
  if not args then return end

  -- Inject -w to capture status code (not shown in the editable curl)
  vim.list_extend(args, { '-w', '\n%{http_code}' })

  local start = vim.uv.hrtime()
  local stdout = {}
  local stderr = {}

  vim.fn.jobstart(vim.list_extend({ 'curl' }, args), {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) stdout = data end,
    on_stderr = function(_, data) stderr = data end,
    on_exit = function()
      vim.schedule(function()
        if not H.detail_buf or not vim.api.nvim_buf_is_valid(H.detail_buf) then return end

        local elapsed = math.floor((vim.uv.hrtime() - start) / 1e6)
        local err = vim.trim(table.concat(stderr, '\n'))

        if err ~= '' then
          ep.last_status = 0
          ep.last_time = elapsed
          ep.last_response = 'Error: ' .. err
        else
          local raw = table.concat(stdout, '\n')
          local curl_mod = require('curls.curl')
          local body, status_code = curl_mod.split_output(raw)
          ep.last_status = status_code
          ep.last_time = elapsed
          ep.last_response = curl_mod.pretty_json(body)
        end

        H.render_detail()
      end)
    end,
  })
end


-- ============================================================================
-- Utilities
-- ============================================================================

H.METHOD_HL = {
  GET = 'CurlsMethodGet',
  POST = 'CurlsMethodPost',
  PUT = 'CurlsMethodPut',
  PATCH = 'CurlsMethodPatch',
  DELETE = 'CurlsMethodDelete',
}

H.setup_highlights = function()
  if H.highlights_set then return end
  H.highlights_set = true

  local hl = vim.api.nvim_set_hl
  hl(0, 'CurlsStatus2xx', { default = true, link = 'DiagnosticOk' })
  hl(0, 'CurlsStatus3xx', { default = true, link = 'DiagnosticInfo' })
  hl(0, 'CurlsStatus4xx', { default = true, link = 'DiagnosticWarn' })
  hl(0, 'CurlsStatus5xx', { default = true, link = 'DiagnosticError' })
  hl(0, 'CurlsStatusErr', { default = true, link = 'DiagnosticError' })
  hl(0, 'CurlsMethodGet', { default = true, link = 'Function' })
  hl(0, 'CurlsMethodPost', { default = true, link = 'Keyword' })
  hl(0, 'CurlsMethodPut', { default = true, link = 'Type' })
  hl(0, 'CurlsMethodPatch', { default = true, link = 'Type' })
  hl(0, 'CurlsMethodDelete', { default = true, link = 'DiagnosticError' })
end

H.highlight_methods = function()
  if not H.list_buf or not vim.api.nvim_buf_is_valid(H.list_buf) then return end

  for i, ep in ipairs(H.endpoints) do
    local hl = H.METHOD_HL[ep.method]
    if hl then
      vim.api.nvim_buf_set_extmark(H.list_buf, H.NS, i - 1, H.METHOD_COL_START, {
        end_col = H.METHOD_COL_END,
        hl_group = hl,
      })
    end
  end
end

H.highlight_status = function(status_code, line_nr)
  if not H.detail_buf or not vim.api.nvim_buf_is_valid(H.detail_buf) then return end

  local hl_group
  if status_code >= 500 then hl_group = 'CurlsStatus5xx'
  elseif status_code >= 400 then hl_group = 'CurlsStatus4xx'
  elseif status_code >= 300 then hl_group = 'CurlsStatus3xx'
  elseif status_code >= 200 then hl_group = 'CurlsStatus2xx'
  else hl_group = 'CurlsStatusErr'
  end

  vim.api.nvim_buf_set_extmark(H.detail_buf, H.NS, line_nr, 0, {
    end_col = 0,
    end_row = line_nr + 1,
    hl_group = hl_group,
  })
end

H.set_lines = function(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

H.reset = function()
  -- Capture any in-progress edits from the detail buffer before saving
  if H.detail_buf and vim.api.nvim_buf_is_valid(H.detail_buf) and H.prev_row then
    local ep = H.endpoints[H.prev_row]
    if ep then
      local buf_lines = vim.api.nvim_buf_get_lines(H.detail_buf, 0, -1, false)
      local curl_lines = {}
      for _, line in ipairs(buf_lines) do
        if vim.trim(line) == '' then break end
        table.insert(curl_lines, line)
      end
      if #curl_lines > 0 then
        ep.edited_curl = curl_lines
      end
    end
  end

  if H.on_close then
    pcall(H.on_close, H.endpoints, H.base_url)
  end

  for _, win in ipairs({ H.list_win, H.detail_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  H.list_win = nil
  H.list_buf = nil
  H.detail_win = nil
  H.detail_buf = nil
  H.endpoints = {}
  H.base_url = nil
  H.on_close = nil
  H.prev_row = nil
  H.help_visible = false
end

return M
