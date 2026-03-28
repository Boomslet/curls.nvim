local M = {} -- Module (public)
local H = {} -- Helpers (private)

H.BODY_METHODS = { POST = true, PUT = true, PATCH = true }

--- Build a curl command as lines from an endpoint.
---@param ep table endpoint from the parser
---@param base_url string
---@return string[]
M.build = function(ep, base_url)
  local url = base_url .. ep.path

  for _, param in ipairs(ep.path_params or {}) do
    url = url:gsub(':' .. param, '{' .. param .. '}')
  end

  local parts = { ('  curl -s -X %s \\'):format(ep.method) }

  if H.BODY_METHODS[ep.method] then
    table.insert(parts, "    -H 'Content-Type: application/json' \\")
    local body = H.build_json_body(H.body_fields(ep))
    table.insert(parts, ("    -d '%s' \\"):format(body))
  end

  table.insert(parts, ("    '%s'"):format(url))

  return parts
end

---@param ep table
---@return table<string, string>
H.body_fields = function(ep)
  local result = {}
  local path_param_set = {}
  for _, p in ipairs(ep.path_params or {}) do path_param_set[p] = true end
  for k, v in pairs(ep.fields or {}) do
    if not path_param_set[k] then result[k] = v end
  end
  return result
end

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

--- Parse a multi-line curl command into an args list.
---@param lines string[]
---@return string[]|nil
M.parse_args = function(lines)
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

  local joined = table.concat(raw, ' ')
  joined = joined:gsub('^curl%s+', '')

  return H.split_shell_args(joined)
end

--- Split curl -w output into body and status code.
---@param raw string
---@return string body, number status_code
M.split_output = function(raw)
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
M.pretty_json = function(str)
  local ok, decoded = pcall(vim.json.decode, str)
  if not ok then return str end
  return H.json_encode(decoded, 0)
end

-- ============================================================================
-- Helpers
-- ============================================================================

H.split_shell_args = function(str)
  local args = {}
  local i = 1
  while i <= #str do
    while i <= #str and str:sub(i, i):match('%s') do i = i + 1 end
    if i > #str then break end

    local c = str:sub(i, i)
    if c == "'" or c == '"' then
      local close = str:find(c, i + 1, true)
      if close then
        table.insert(args, str:sub(i + 1, close - 1))
        i = close + 1
      else
        table.insert(args, str:sub(i + 1))
        break
      end
    else
      local start = i
      while i <= #str and not str:sub(i, i):match('[%s\'"]') do i = i + 1 end
      table.insert(args, str:sub(start, i - 1))
    end
  end
  return args
end

H.json_encode = function(val, indent)
  local pad = string.rep('  ', indent)
  local inner = string.rep('  ', indent + 1)

  if type(val) == 'table' then
    if vim.islist(val) then
      if #val == 0 then return '[]' end
      local items = {}
      for _, v in ipairs(val) do
        table.insert(items, inner .. H.json_encode(v, indent + 1))
      end
      return '[\n' .. table.concat(items, ',\n') .. '\n' .. pad .. ']'
    else
      local keys = vim.tbl_keys(val)
      if #keys == 0 then return '{}' end
      table.sort(keys)
      local items = {}
      for _, k in ipairs(keys) do
        table.insert(items, inner .. vim.json.encode(k) .. ': ' .. H.json_encode(val[k], indent + 1))
      end
      return '{\n' .. table.concat(items, ',\n') .. '\n' .. pad .. '}'
    end
  end

  return vim.json.encode(val)
end

return M
