local M = {} -- Module (public)
local H = {} -- Helpers (private)

-- Panel state
H.win = nil
H.buf = nil

--- Open the floating panel.
M.open = function()
  if H.win and vim.api.nvim_win_is_valid(H.win) then
    return
  end

  H.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[H.buf].bufhidden = 'wipe'

  local win_opts = H.win_config()
  H.win = vim.api.nvim_open_win(H.buf, true, win_opts)

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

--- Build the float window config (80% of screen, centered).
---@return table
H.win_config = function()
  return {
    relative = 'editor',
    width = 0.8,
    height = 0.8,
    anchor = 'NW',
    row = 0.1,
    col = 0.1,
    style = 'minimal',
    border = 'rounded',
    title = ' curls ',
    title_pos = 'center',
  }
end

return M
