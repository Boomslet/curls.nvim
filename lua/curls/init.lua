local M = {} -- Module (public)
local H = {} -- Helpers (private)

M.config = {
  base_url = nil,
}

H.DEFAULT_BASE_URL = 'http://localhost:4000'

M.state = {
  base_url = nil,
}

---@param opts? table
M.setup = function(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)

  -- Load persisted data, config takes precedence
  local store = require('curls.store')
  local saved = store.load()

  M.state.base_url = M.config.base_url or saved.base_url or H.DEFAULT_BASE_URL
  M.state.saved_curls = saved.curls or {}

  H.create_commands()
end

M.open = function()
  local source_buf = vim.api.nvim_get_current_buf()
  local ui = require('curls.ui')
  ui.open(source_buf, {
    base_url = M.state.base_url,
    saved_curls = M.state.saved_curls,
    on_close = M.save,
  })
end

--- Save current state to disk. Called by UI on panel close.
M.save = function(endpoints, base_url)
  if base_url then
    M.state.base_url = base_url
  end

  local store = require('curls.store')
  local curls = {}
  for _, ep in ipairs(endpoints or {}) do
    if ep.edited_curl then
      curls[store.endpoint_key(ep)] = ep.edited_curl
    end
  end

  store.save({
    base_url = M.state.base_url,
    curls = curls,
  })

  M.state.saved_curls = curls
end

-- ============================================================================
-- Helpers
-- ============================================================================

H.create_commands = function()
  vim.api.nvim_create_user_command('Curls', function() M.open() end, {})
end

return M
