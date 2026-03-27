local M = {} -- Module (public)
local H = {} -- Helpers (private)

H.STREAM_VARIANTS = {
  streamOut = true,
  streamIn = true,
  streamInOut = true,
}

H.TYPE_DEFAULTS = {
  string = '""',
  number = '0',
  boolean = 'true',
}

--- Parse all Encore.ts endpoints in a buffer.
---@param bufnr number
---@return table[] endpoints
M.parse_buffer = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'typescript')
  if not ok or not parser then return {} end

  local trees = parser:parse()
  if not trees or #trees == 0 then return {} end

  local query = H.get_query()
  if not query then return {} end

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

---@return vim.treesitter.Query|nil
H.get_query = function()
  local ok, query = pcall(vim.treesitter.query.get, 'typescript', 'curls')
  if ok and query then return query end
  return nil
end

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
  local variant = captures['endpoint.variant']
      and vim.treesitter.get_node_text(captures['endpoint.variant'], bufnr)
      or nil
  local is_stream = variant and H.STREAM_VARIANTS[variant] or false

  local method = config.method or (is_stream and 'POST' or 'GET')
  local path = config.path or ('/' .. name)

  local fields = {}
  if is_stream and captures['endpoint.type_args'] then
    fields = H.resolve_type_args(captures['endpoint.type_args'], bufnr)
  elseif captures['endpoint.handler'] then
    local type_node = H.extract_handler_type(captures['endpoint.handler'], bufnr)
    if type_node then
      fields = H.resolve_object_type(type_node, bufnr)
    end
  end

  return {
    name = name,
    line = captures['endpoint.name']:start() + 1,
    method = method:upper(),
    path = path,
    path_params = H.extract_path_params(path),
    fields = fields,
    stream = is_stream,
  }
end

-- ============================================================================
-- Config extraction
-- ============================================================================

H.extract_config = function(node, bufnr)
  local config = {}
  for child in node:iter_children() do
    if child:type() == 'pair' then
      local key_node = child:child(0)
      local val_node = child:child(2)
      if key_node and val_node then
        local key = vim.treesitter.get_node_text(key_node, bufnr):gsub('["\']', '')
        local val = vim.treesitter.get_node_text(val_node, bufnr):gsub('^["\']', ''):gsub('["\']$', '')
        config[key] = val
      end
    end
  end
  return config
end

---@param path string e.g. "/items/:id/sub/:subId"
---@return string[]
H.extract_path_params = function(path)
  local params = {}
  for param in path:gmatch(':([%w_]+)') do
    table.insert(params, param)
  end
  return params
end

-- ============================================================================
-- Type resolution
-- ============================================================================

--- Find the first child of a node matching a given type.
---@param node TSNode
---@param type_name string
---@return TSNode|nil
H.find_child = function(node, type_name)
  for child in node:iter_children() do
    if child:type() == type_name then
      return child
    end
  end
  return nil
end

--- Extract the first type argument from type_arguments node.
H.resolve_type_args = function(type_args_node, bufnr)
  for child in type_args_node:iter_children() do
    local t = child:type()
    if t ~= '<' and t ~= '>' and t ~= ',' then
      return H.resolve_object_type(child, bufnr)
    end
  end
  return {}
end

--- Extract the type annotation from the handler's first parameter.
H.extract_handler_type = function(handler_node, bufnr)
  local params = H.find_child(handler_node, 'formal_parameters')
  if not params then return nil end

  local param = H.find_child(params, 'required_parameter')
  if not param then return nil end

  local annotation = H.find_child(param, 'type_annotation')
  if not annotation then return nil end

  -- Return the first non-colon child (the actual type node)
  for child in annotation:iter_children() do
    if child:type() ~= ':' then
      return child
    end
  end
  return nil
end

--- Resolve an object type node into a table of { field_name = placeholder_value }.
H.resolve_object_type = function(node, bufnr)
  local fields = {}

  if node:type() ~= 'object_type' then return fields end

  for child in node:iter_children() do
    if child:type() == 'property_signature' then
      local field_name, field_value = H.resolve_property(child, bufnr)
      if field_name then
        fields[field_name] = field_value
      end
    end
  end

  return fields
end

--- Resolve a single property_signature into a name and placeholder value.
H.resolve_property = function(node, bufnr)
  local name = nil
  local value = '"TODO"'

  for child in node:iter_children() do
    if child:type() == 'property_identifier' then
      name = vim.treesitter.get_node_text(child, bufnr)
    elseif child:type() == 'type_annotation' then
      for type_child in child:iter_children() do
        value = H.resolve_type_node(type_child, bufnr) or value
      end
    end
  end

  return name, value
end

--- Resolve a single type node to its placeholder value.
---@return string|nil
H.resolve_type_node = function(node, bufnr)
  local t = node:type()

  if t == 'predefined_type' or t == 'type_identifier' then
    local type_name = vim.treesitter.get_node_text(node, bufnr)
    return H.TYPE_DEFAULTS[type_name]
  elseif t == 'array_type' then
    return '[]'
  elseif t == 'object_type' then
    return '{}'
  elseif t == 'union_type' then
    for member in node:iter_children() do
      local resolved = H.resolve_type_node(member, bufnr)
      if resolved then return resolved end
    end
  end

  return nil
end

return M
