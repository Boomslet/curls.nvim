local M = {} -- Module (public)
local H = {} -- Helpers (private)

H.BODY_METHODS = { POST = true, PUT = true, PATCH = true }
H.NS = vim.api.nvim_create_namespace('curls')

-- Default highlight groups — users can override by defining these before loading the plugin
vim.api.nvim_set_hl(0, 'CurlsStatus2xx', { default = true, link = 'DiagnosticOk' })
vim.api.nvim_set_hl(0, 'CurlsStatus3xx', { default = true, link = 'DiagnosticInfo' })
vim.api.nvim_set_hl(0, 'CurlsStatus4xx', { default = true, link = 'DiagnosticWarn' })
vim.api.nvim_set_hl(0, 'CurlsStatus5xx', { default = true, link = 'DiagnosticError' })
vim.api.nvim_set_hl(0, 'CurlsStatusErr', { default = true, link = 'DiagnosticError' })
vim.api.nvim_set_hl(0, 'CurlsMethodGet', { default = true, link = 'Function' })
vim.api.nvim_set_hl(0, 'CurlsMethodPost', { default = true, link = 'Keyword' })
vim.api.nvim_set_hl(0, 'CurlsMethodPut', { default = true, link = 'Type' })
vim.api.nvim_set_hl(0, 'CurlsMethodPatch', { default = true, link = 'Type' })
vim.api.nvim_set_hl(0, 'CurlsMethodDelete', { default = true, link = 'DiagnosticError' })

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
H.prev_row = nil
H.help_visible = false

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
  H.render_help()
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
    footer = ' Enter:edit  Space:fire  ?:close help '
  else
    footer = ' ? for help '
  end

  vim.api.nvim_win_set_config(H.list_win, { footer = footer, footer_pos = 'right' })
end

H.render_detail = function()
  local ep = H.endpoints[H.prev_row]
  if not ep then return end

  -- Use saved curl lines if the user has edited them, otherwise generate fresh
  local curl_lines = ep.edited_curl or H.build_curl(ep)
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
    local body_fields = {}
    local path_param_set = {}
    for _, p in ipairs(ep.path_params or {}) do path_param_set[p] = true end
    for k, v in pairs(ep.fields or {}) do
      if not path_param_set[k] then body_fields[k] = v end
    end
    local body = H.build_json_body(body_fields)
    table.insert(parts, ("    -d '%s' \\"):format(body))
  end

  table.insert(parts, ("    '%s'"):format(url))

  return parts
end

--- Build a JSON body string from resolved type fields.
---@param fields table<string, string>
---@return string
H.build_json_body = function(fields)
  if vim.tbl_isempty(fields) then return '{}' end

  local pairs_list = {}
  for k, v in pairs(fields) do
    table.insert(pairs_list, ('"%s": %s'):format(k, v))
  end
  table.sort(pairs_list)

  return '{ ' .. table.concat(pairs_list, ', ') .. ' }'
end

-- ============================================================================
-- Execution
-- ============================================================================

H.execute_curl = function()
  local ep = H.endpoints[H.prev_row]
  if not ep then return end

  -- Read the curl from the detail buffer (respects user edits)
  local detail_lines = vim.api.nvim_buf_get_lines(H.detail_buf, 0, -1, false)
  local args = H.parse_curl_args(detail_lines)
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
          local body, status_code = H.split_curl_output(raw)
          ep.last_status = status_code
          ep.last_time = elapsed
          ep.last_response = H.pretty_json(body)
        end

        H.render_detail()
      end)
    end,
  })
end

--- Parse the curl command from detail buffer lines into an args list.
--- Strips the leading 'curl' word and joins continuation lines.
---@param lines string[]
---@return string[]|nil
H.parse_curl_args = function(lines)
  local raw = {}
  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed == '' then break end
    trimmed = trimmed:gsub('%s*\\$', '')
    if trimmed ~= '' then
      table.insert(raw, trimmed)
    end
  end
  if #raw == 0 then return nil end

  -- Join into one string, strip leading 'curl', then split into args
  local joined = table.concat(raw, ' ')
  joined = joined:gsub('^curl%s+', '')

  -- Shell-like arg splitting (respects single and double quotes)
  local args = {}
  local i = 1
  while i <= #joined do
    -- Skip whitespace
    while i <= #joined and joined:sub(i, i):match('%s') do i = i + 1 end
    if i > #joined then break end

    local c = joined:sub(i, i)
    if c == "'" or c == '"' then
      -- Quoted arg: find matching close quote
      local close = joined:find(c, i + 1, true)
      if close then
        table.insert(args, joined:sub(i + 1, close - 1))
        i = close + 1
      else
        table.insert(args, joined:sub(i + 1))
        break
      end
    else
      -- Unquoted arg: read until whitespace or quote
      local start = i
      while i <= #joined and not joined:sub(i, i):match('[%s\'"]') do i = i + 1 end
      table.insert(args, joined:sub(start, i - 1))
    end
  end

  return args
end

--- Split curl -w output: body is everything except the last line (status code).
---@param raw string
---@return string body, number status_code
H.split_curl_output = function(raw)
  local lines = vim.split(raw, '\n')
  while #lines > 0 and lines[#lines] == '' do
    table.remove(lines)
  end
  local status_code = tonumber(table.remove(lines) or '') or 0
  return table.concat(lines, '\n'), status_code
end

--- Pretty-print JSON if possible, otherwise return as-is.
---@param str string
---@return string
H.pretty_json = function(str)
  local ok, decoded = pcall(vim.json.decode, str)
  if not ok then return str end
  return H.json_encode_pretty(decoded, 0)
end

---@param val any
---@param indent number
---@return string
H.json_encode_pretty = function(val, indent)
  local pad = string.rep('  ', indent)
  local inner = string.rep('  ', indent + 1)

  if type(val) == 'table' then
    if vim.islist(val) then
      if #val == 0 then return '[]' end
      local items = {}
      for _, v in ipairs(val) do
        table.insert(items, inner .. H.json_encode_pretty(v, indent + 1))
      end
      return '[\n' .. table.concat(items, ',\n') .. '\n' .. pad .. ']'
    else
      local keys = vim.tbl_keys(val)
      if #keys == 0 then return '{}' end
      table.sort(keys)
      local items = {}
      for _, k in ipairs(keys) do
        table.insert(items, inner .. vim.json.encode(k) .. ': ' .. H.json_encode_pretty(val[k], indent + 1))
      end
      return '{\n' .. table.concat(items, ',\n') .. '\n' .. pad .. '}'
    end
  end

  return vim.json.encode(val)
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

H.set_lines = function(buf, lines, start, stop)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, start or 0, stop or -1, false, lines)
  vim.bo[buf].modifiable = false
end

H.reset = function()
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
  H.prev_row = nil
  H.help_visible = false
end

return M
