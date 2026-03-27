local parse = require('curls.parse')

local function load_fixture(name)
  local path = vim.fn.fnamemodify('tests/fixtures/' .. name, ':p')
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(path))
  vim.bo[buf].filetype = 'typescript'
  vim.treesitter.start(buf, 'typescript')
  vim.treesitter.get_parser(buf, 'typescript'):parse()
  return buf
end

local function index_by_name(endpoints)
  local map = {}
  for _, ep in ipairs(endpoints) do
    map[ep.name] = ep
  end
  return map
end

describe('parse', function()
  local endpoints, by_name
  local buf

  before_each(function()
    buf = load_fixture('encore.ts')
    endpoints = parse.parse_buffer(buf)
    by_name = index_by_name(endpoints)
  end)

  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it('finds all endpoints', function()
    assert.equals(12, #endpoints)
  end)

  describe('standard api()', function()
    it('GET with explicit method', function()
      assert.equals('GET', by_name.getHealth.method)
      assert.equals('/api/health', by_name.getHealth.path)
      assert.same({}, by_name.getHealth.fields)
    end)

    it('POST with inline request type fields', function()
      assert.equals('POST', by_name.createUser.method)
      assert.equals('/api/users', by_name.createUser.path)
      assert.equals('""', by_name.createUser.fields.name)
      assert.equals('""', by_name.createUser.fields.email)
      assert.equals('0', by_name.createUser.fields.age)
    end)

    it('defaults to GET when no method specified', function()
      assert.equals('GET', by_name.getItem.method)
    end)

    it('extracts path params', function()
      assert.same({ 'id' }, by_name.getItem.path_params)
    end)

    it('PUT with path params and body fields', function()
      assert.equals('PUT', by_name.updateItem.method)
      assert.equals('/api/items/:id', by_name.updateItem.path)
      assert.same({ 'id' }, by_name.updateItem.path_params)
      assert.equals('""', by_name.updateItem.fields.id)
      assert.equals('""', by_name.updateItem.fields.name)
      assert.equals('0', by_name.updateItem.fields.count)
      assert.equals('true', by_name.updateItem.fields.active)
    end)

    it('defaults path to /endpointName when omitted', function()
      assert.equals('/defaultEndpoint', by_name.defaultEndpoint.path)
    end)

    it('DELETE', function()
      assert.equals('DELETE', by_name.deleteItem.method)
    end)

    it('PATCH', function()
      assert.equals('PATCH', by_name.patchItem.method)
    end)

    it('optional and union types resolve to base type', function()
      assert.equals('""', by_name.processData.fields.data)
      assert.equals('""', by_name.processData.fields.format)
      assert.equals('""', by_name.processData.fields.callback)
    end)

    it('array types resolve to []', function()
      assert.equals('[]', by_name.patchItem.fields.tags)
    end)

    it('nested object types resolve to {}', function()
      assert.equals('{}', by_name.patchItem.fields.metadata)
    end)

    it('named type references return empty fields', function()
      assert.same({}, by_name.search.fields)
    end)
  end)

  describe('stream variants', function()
    it('streamOut', function()
      assert.equals('POST', by_name.streamEvents.method)
      assert.equals('/api/events/:channel', by_name.streamEvents.path)
      assert.is_true(by_name.streamEvents.stream)
      assert.equals('""', by_name.streamEvents.fields.channel)
    end)

    it('streamIn', function()
      assert.equals('POST', by_name.uploadChunks.method)
      assert.is_true(by_name.uploadChunks.stream)
      assert.equals('""', by_name.uploadChunks.fields.uploadId)
      assert.equals('""', by_name.uploadChunks.fields.chunk)
    end)

    it('streamInOut', function()
      assert.equals('POST', by_name.chat.method)
      assert.is_true(by_name.chat.stream)
      assert.equals('""', by_name.chat.fields.message)
      assert.equals('""', by_name.chat.fields.sessionId)
    end)

    it('only resolves request type, not response type', function()
      assert.equals('""', by_name.streamEvents.fields.channel)
      assert.is_nil(by_name.streamEvents.fields.event)
      assert.is_nil(by_name.streamEvents.fields.data)
    end)
  end)

  describe('source order', function()
    it('endpoints appear in file order', function()
      local names = vim.tbl_map(function(ep) return ep.name end, endpoints)
      assert.same({
        'getHealth', 'createUser', 'getItem', 'updateItem', 'defaultEndpoint',
        'streamEvents', 'uploadChunks', 'chat', 'processData', 'deleteItem',
        'patchItem', 'search',
      }, names)
    end)
  end)
end)
