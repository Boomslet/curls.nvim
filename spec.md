# curls.nvim

A Neovim plugin that reads your TypeScript source code, finds API endpoint declarations, resolves the request types from your TS interfaces, and lets you build and execute curls without leaving the editor.

Encore.ts first. Extensible to Express, Hono, Next.js later.

## Core workflow

1. You're editing a TS file. Cursor is on or near an `api()` call.
2. You trigger `:CurlsRun` (or a keymap).
3. The plugin parses the endpoint — method, path, request body fields from the TS types.
4. An editable buffer opens in a split with the curl pre-filled: method, URL with path param placeholders, JSON body scaffolded from the resolved types.
5. You fill in real values, hit `<CR>` to execute.
6. A split buffer opens below showing the response — syntax-highlighted JSON with status code and timing.

## Parsing

- **Treesitter** finds Encore.ts `api()` and `api.raw()` calls in the current buffer.
- Extracts: endpoint name, HTTP method, path (with `:param` segments), request type annotation.
- **LSP hover** resolves named types into their fields. Inline object types (`{ id: string }`) parsed directly from treesitter — no LSP needed.
- Fields classified as:
  - **path** — matches a `:param` in the path
  - **query** — non-path fields on GET/HEAD/DELETE
  - **body** — non-path fields on POST/PUT/PATCH

## Type resolution

This is the whole point — you shouldn't have to look up what fields an endpoint expects.

- TS types mapped to placeholder values: `string` → `"example"`, `number` → `0`, `boolean` → `true`, arrays → `[placeholder]`.
- Nested objects resolved one level deep.
- Unknown types → `"TODO"`.

## Base URL

- Prompted via `vim.ui.input` on first run. Remembered for the session.
- Can be pre-configured in `setup()` if desired.

## Editable curl buffer

- Opens as a **split** (not floating) so it stays accessible while you reference other code.
- Curl formatted multi-line for readability:
  ```
  curl \
    -s -X POST \
    -H 'Content-Type: application/json' \
    -d '{
      "name": "example",
      "count": 0
    }' \
    'http://localhost:4000/items/{id}'
  ```
- Edit values in place, `<CR>` to execute, `q` to close.
- Last-used values saved to the persistence file so they pre-fill next time.

## Response viewer

- Opens in a **split buffer** below the curl editor.
- Syntax-highlighted JSON (filetype set to `json`), foldable for large responses.
- Header line shows: status code, response time.

## Persistence

Saves to `.curls.json` at project root. Stores:

- **Discovered endpoints**: name, file, line, method, path, resolved fields.
- **User values**: the actual IDs, tokens, body values you typed in — pre-filled on next run.
- **Response history**: last N responses per endpoint (timestamp, status code, body).

Human-readable, optionally version-controllable.

## Framework support

Encore.ts first:
- `api({ method, path, expose, auth }, handler)` — standard endpoints
- `api.raw({ method, path, ... }, handler)` — raw HTTP endpoints

Extensible: each framework is a parser module implementing the same interface. Express, Hono, Next.js planned for later.

## Commands

- `:CurlsRun` — parse endpoint at cursor, open editable curl, execute on `<CR>`
- `:CurlsList` — pick from all known endpoints in the project
- `:CurlsEnv [url]` — set/change the base URL
- `:CurlsScan` — re-scan current buffer; `:CurlsScan!` for full project

## Style

- mini.nvim conventions: `M` + `H` pattern, single-file modules, no external dependencies.
- Zero config required — works with just `require('curls').setup()`.
