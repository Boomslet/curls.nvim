local M = {} -- Module (public)
local H = {} -- Helpers (private)

--- Parse all Encore.ts endpoints in a buffer.
---@param bufnr number
---@return table[] endpoints
M.parse_buffer = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'typescript')
  if not ok or not parser then
    return {}
  end

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return {}
  end

  local query = H.get_query()
  if not query then
    return {}
  end

  local root = trees[1]:root()
  local endpoints = {}

  for _, match, _ in query:iter_matches(root, bufnr) do
    local endpoint = H.extract_endpoint(match, query, bufnr)
    if endpoint then
      table.insert(endpoints, endpoint)
    end
  end

  return endpoints
end

-- ============================================================================
-- Helpers
-- ============================================================================

--- Load the treesitter query from the .scm file.
---@return vim.treesitter.Query|nil
H.get_query = function()
  -- Cache after first load
  if H.cached_query then
    return H.cached_query
  end

  local ok, query = pcall(vim.treesitter.query.get, 'typescript', 'curls')
  if ok and query then
    H.cached_query = query
    return query
  end

  return nil
end

H.cached_query = nil

--- Extract a single endpoint from a treesitter match.
H.extract_endpoint = function(match, query, bufnr)
  local captures = {}
  for id, nodes in pairs(match) do
    local name = query.captures[id]
    captures[name] = type(nodes) == 'table' and nodes[1] or nodes
  end

  if not captures['endpoint.name'] or not captures['endpoint.config'] then
    return nil
  end

  local name = vim.treesitter.get_node_text(captures['endpoint.name'], bufnr)
  local config = H.extract_config(captures['endpoint.config'], bufnr)
  local raw = captures['endpoint.variant'] ~= nil

  local method = config.method or (raw and '*' or 'GET')
  local path = config.path or ('/' .. name)

  local request_type_node = nil
  local request_type_name = nil
  if not raw and captures['endpoint.handler'] then
    request_type_node, request_type_name = H.extract_request_type(captures['endpoint.handler'], bufnr)
  end

  local line = captures['endpoint.name']:start()

  return {
    name = name,
    file = vim.api.nvim_buf_get_name(bufnr),
    line = line + 1,
    method = method:upper(),
    path = path,
    path_params = H.extract_path_params(path),
    raw = raw,
    expose = config.expose == 'true',
    auth = config.auth == 'true',
    request_type_node = request_type_node,
    request_type_name = request_type_name,
  }
end

--- Walk a config object node and extract key-value pairs.
H.extract_config = function(node, bufnr)
  local config = {}
  for child in node:iter_children() do
    if child:type() == 'pair' then
      local key_node = child:child(0)
      local val_node = child:child(2)
      if key_node and val_node then
        local key = vim.treesitter.get_node_text(key_node, bufnr)
        local val = vim.treesitter.get_node_text(val_node, bufnr)
        key = key:gsub('["\']', '')
        val = val:gsub('^["\']', ''):gsub('["\']$', '')
        config[key] = val
      end
    end
  end
  return config
end

--- Extract the request type annotation from the handler function node.
H.extract_request_type = function(handler_node, bufnr)
  local params_node = nil
  for child in handler_node:iter_children() do
    if child:type() == 'formal_parameters' then
      params_node = child
      break
    end
  end

  if not params_node then
    return nil, nil
  end

  for child in params_node:iter_children() do
    if child:type() == 'required_parameter' then
      for sub in child:iter_children() do
        if sub:type() == 'type_annotation' then
          for type_child in sub:iter_children() do
            if type_child:type() ~= ':' then
              local type_text = vim.treesitter.get_node_text(type_child, bufnr)
              return type_child, type_text
            end
          end
        end
      end
    end
  end

  return nil, nil
end

--- Extract path parameter names from a path string.
---@param path string e.g. "/items/:id/sub/:subId"
---@return string[]
H.extract_path_params = function(path)
  local params = {}
  for param in path:gmatch(':([%w_]+)') do
    table.insert(params, param)
  end
  return params
end

return M
