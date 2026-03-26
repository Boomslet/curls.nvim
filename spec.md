# curls.nvim

A Neovim plugin that reads your TypeScript source code, finds API endpoint declarations, resolves the request types from your TS interfaces, and lets you build and execute curls without leaving the editor.

Encore.ts first. Extensible to Express, Hono, Next.js later.

## Core workflow

1. You're editing a TS file with Encore.ts endpoints.
2. You trigger `:Curls`.
3. A floating panel opens (80% of screen) showing all endpoints in the current file, listed in source order.
4. Navigate with `j`/`k`. The bottom section shows the pre-filled curl for the selected endpoint.
5. Press `i` to edit the curl values in place. Press `<Esc>` to return to the list.
6. Press `<Space>` to fire the curl. Response appears below the curl in the detail section — syntax-highlighted JSON with status code and timing.

## The panel

Two-section floating window, 80% of screen, centered.

**Top: endpoint list**

```
 GET  /items/:id         [200 42ms]
 POST /users             [—]
 PUT  /items/:id         [200 18ms]
```

- Endpoints from the current buffer, listed in the order they appear in source.
- Status indicators show last response: `[200 42ms]`, `[404 12ms]`, or `[—]` for never-run.
- `j`/`k` to navigate. Selection updates the detail section below.
- `Y` to yank the curl to clipboard.

**Bottom: detail section**

Shows the curl command for the selected endpoint, and the last response if one exists.

```
curl \
  -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "example",
    "count": 0
  }' \
  'http://localhost:4000/items/{id}'

{ "id": 1, "name": "Widget" }
```

- `i` drops the cursor into this section to edit values. Normal vim editing. `<Esc>` returns focus to the list.
- `<Space>` executes the curl. Response replaces the previous response below the curl.
- Response is syntax-highlighted JSON. Header line shows status code and response time.

## Keybindings

| Key       | Context | Action                              |
|-----------|---------|-------------------------------------|
| `j`/`k`   | list    | Navigate endpoints                  |
| `<Space>` | list    | Fire the curl                       |
| `<CR>`    | list    | Edit curl in detail section         |
| `<Esc>`   | edit    | Return to list                      |
| `?`       | any     | Toggle help line at bottom          |

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

## Scanning & persistence

Saves to `.curls.json` at project root.

**Scanning:**
- Endpoints are scanned and cached on first `:Curls`.
- Every subsequent open re-scans for new endpoints and merges them in, but keeps existing user values and endpoint ordering intact.

**Stored data:**
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

- `:Curls` — open the panel for the current file. Close with `:q`.

## Style

- mini.nvim conventions: `M` + `H` pattern, single-file modules, no external dependencies.
- Zero config required — works with just `require('curls').setup()`.
