local M = {} -- Module (public)
local H = {} -- Helpers (private)

H.DIR = vim.fn.stdpath('data') .. '/curls'

--- Load persisted data for the current project.
---@return table { base_url?: string, curls?: table<string, string[]> }
M.load = function()
  local path = H.store_path()
  local content = H.read_file(path)
  if not content then return {} end

  local ok, data = pcall(vim.json.decode, content)
  if not ok then return {} end
  return data
end

--- Save data for the current project.
---@param data table { base_url?: string, curls?: table<string, string[]> }
M.save = function(data)
  vim.fn.mkdir(H.DIR, 'p')
  local path = H.store_path()
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then return end
  H.write_file(path, encoded)
end

--- Build a unique key for an endpoint (used to match persisted curls).
---@param ep table
---@return string
M.endpoint_key = function(ep)
  return ep.method .. ' ' .. ep.path
end

-- ============================================================================
-- Helpers
-- ============================================================================

H.store_path = function()
  local key = H.project_key()
  local hash = vim.fn.sha256(key):sub(1, 12)
  return H.DIR .. '/' .. hash .. '.json'
end

H.project_key = function()
  -- Try git remote origin URL first
  local remote = vim.fn.system('git remote get-url origin 2>/dev/null'):gsub('%s+$', '')
  if vim.v.shell_error == 0 and remote ~= '' then
    return remote
  end
  -- Fallback to working directory
  return vim.fn.getcwd()
end

H.read_file = function(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  return content
end

H.write_file = function(path, content)
  local f = io.open(path, 'w')
  if not f then return end
  f:write(content)
  f:close()
end

return M
