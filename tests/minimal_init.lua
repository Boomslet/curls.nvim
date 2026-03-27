vim.opt.rtp:prepend('.')

-- Try local test deps first, then lazy.nvim install paths
local search_paths = {
  '.test-deps',
  vim.fn.stdpath('data') .. '/lazy',
}

for _, base in ipairs(search_paths) do
  for _, dep in ipairs({ 'plenary.nvim', 'nvim-treesitter' }) do
    local path = base .. '/' .. dep
    if vim.fn.isdirectory(path) == 1 then
      vim.opt.rtp:prepend(path)
    end
  end
end

pcall(require, 'nvim-treesitter')
