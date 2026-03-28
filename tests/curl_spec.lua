local curl = require('curls.curl')

local BASE = 'http://localhost:4000'

describe('curl', function()
  describe('build', function()
    it('GET with no body', function()
      local ep = { method = 'GET', path = '/api/health', path_params = {}, fields = {} }
      local lines = curl.build(ep, BASE)
      assert.equals(2, #lines)
      assert.truthy(lines[1]:find('-X GET'))
      assert.truthy(lines[2]:find('/api/health'))
    end)

    it('POST with body fields', function()
      local ep = {
        method = 'POST', path = '/api/users', path_params = {},
        fields = { name = '""', age = '0' },
      }
      local lines = curl.build(ep, BASE)
      assert.equals(4, #lines)
      assert.truthy(lines[2]:find('Content%-Type'))
      assert.truthy(lines[3]:find('"age": 0'))
      assert.truthy(lines[3]:find('"name": ""'))
    end)

    it('replaces path params in the URL', function()
      local ep = { method = 'GET', path = '/items/:id', path_params = { 'id' }, fields = {} }
      local lines = curl.build(ep, BASE)
      assert.truthy(lines[2]:find('{id}'))
    end)

    it('excludes path params from the body', function()
      local ep = {
        method = 'PUT', path = '/items/:id', path_params = { 'id' },
        fields = { id = '""', name = '""' },
      }
      local lines = curl.build(ep, BASE)
      local body_line = lines[3]
      assert.truthy(body_line:find('"name"'))
      assert.is_nil(body_line:find('"id"'))
    end)
  end)

  describe('parse_args round-trip', function()
    it('parses back what build produces (GET)', function()
      local ep = { method = 'GET', path = '/api/health', path_params = {}, fields = {} }
      local lines = curl.build(ep, BASE)
      local args = curl.parse_args(lines)
      assert.truthy(vim.tbl_contains(args, '-X'))
      assert.truthy(vim.tbl_contains(args, 'GET'))
      assert.truthy(vim.tbl_contains(args, BASE .. '/api/health'))
    end)

    it('parses back what build produces (POST with body)', function()
      local ep = {
        method = 'POST', path = '/api/users', path_params = {},
        fields = { name = '""' },
      }
      local lines = curl.build(ep, BASE)
      local args = curl.parse_args(lines)
      assert.truthy(vim.tbl_contains(args, '-d'))
      assert.truthy(vim.tbl_contains(args, 'POST'))
    end)

    it('stops at empty line', function()
      local args = curl.parse_args({ '  curl -s -X GET \\', "    'http://x'", '', 'junk' })
      assert.equals(4, #args)
    end)

    it('returns nil for empty input', function()
      assert.is_nil(curl.parse_args({}))
    end)
  end)

  describe('split_output', function()
    it('extracts status code from last line', function()
      local body, code = curl.split_output('{"ok":true}\n200')
      assert.equals('{"ok":true}', body)
      assert.equals(200, code)
    end)

    it('handles trailing newlines', function()
      local _, code = curl.split_output('body\n200\n\n')
      assert.equals(200, code)
    end)

    it('returns 0 for empty input', function()
      local _, code = curl.split_output('')
      assert.equals(0, code)
    end)

    it('handles multi-line body', function()
      local body, code = curl.split_output('line1\nline2\n404')
      assert.equals('line1\nline2', body)
      assert.equals(404, code)
    end)
  end)

  describe('pretty_json', function()
    it('formats valid JSON', function()
      local result = curl.pretty_json('{"b":2,"a":1}')
      assert.truthy(result:find('"a"'))
    end)

    it('returns non-JSON as-is', function()
      assert.equals('nope', curl.pretty_json('nope'))
    end)

    it('handles empty structures', function()
      assert.equals('{}', curl.pretty_json('{}'))
      assert.equals('[]', curl.pretty_json('[]'))
    end)
  end)
end)
