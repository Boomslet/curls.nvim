local M = {} -- Module (public)
local H = {} -- Helpers (private)

M.config = {
  base_url = nil, -- prompted on first run if nil
}

-- Shared state across modules.
M.state = {
  base_url = nil,
  panel_open = false,
}

--- Setup the plugin. Call with require('curls').setup() or require('curls').setup({ base_url = '...' }).
---@param opts? table
M.setup = function(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)

  if M.config.base_url then
    M.state.base_url = M.config.base_url
  end

  H.create_commands()
end

--- Open the curls panel for the current buffer.
M.open = function()
  local source_buf = vim.api.nvim_get_current_buf()
  H.ensure_base_url(function()
    local ui = require('curls.ui')
    ui.open(source_buf, M.state.base_url)
  end)
end

-- ============================================================================
-- Helpers
-- ============================================================================

H.create_commands = function()
  vim.api.nvim_create_user_command('Curls', function() M.open() end, {})
end

--- Prompt for base URL if not set, then call the callback.
---@param callback function
H.ensure_base_url = function(callback)
  if M.state.base_url then
    callback()
    return
  end

  vim.ui.input({ prompt = 'Base URL: ', default = 'http://localhost:4000' }, function(input)
    if not input or input == '' then
      return
    end
    -- Strip trailing slash
    M.state.base_url = input:gsub('/$', '')
    callback()
  end)
end

return M
