local M = {} -- Module (public)
local H = {} -- Helpers (private)

H.DEFAULT_BASE_URL = 'http://localhost:4000'

M.config = {
  base_url = nil,
}

M.state = {
  base_url = nil,
  saved_curls = {},
}

---@param opts? table
M.setup = function(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)

  local store = require('curls.store')
  local saved = store.load()

  M.state.base_url = M.config.base_url or saved.base_url or H.DEFAULT_BASE_URL
  M.state.saved_curls = saved.curls or {}

  vim.api.nvim_create_user_command('Curls', function() M.open() end, {})
end

M.open = function()
  local source_buf = vim.api.nvim_get_current_buf()
  require('curls.ui').open(source_buf, {
    base_url = M.state.base_url,
    saved_curls = M.state.saved_curls,
    on_close = M.save,
  })
end

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

return M
