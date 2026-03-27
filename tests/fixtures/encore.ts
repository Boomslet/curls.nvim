import { api } from "encore.dev/api";

// Standard GET with no body
export const getHealth = api(
  { method: "GET", path: "/api/health", expose: true },
  async () => {
    return { status: "ok" };
  },
);

// POST with inline request type
export const createUser = api(
  { method: "POST", path: "/api/users", expose: true },
  async (req: { name: string; email: string; age: number }) => {
    return { id: 1, ...req };
  },
);

// GET with path params
export const getItem = api(
  { path: "/api/items/:id" },
  async (req: { id: string }) => {
    return { id: req.id, name: "Widget" };
  },
);

// PUT with path params and body fields
export const updateItem = api(
  { method: "PUT", path: "/api/items/:id" },
  async (req: { id: string; name: string; count: number; active: boolean }) => {
    return { updated: true };
  },
);

// No method specified, no path specified — defaults to GET and /functionName
export const defaultEndpoint = api(
  { expose: true },
  async (req: { query: string }) => {
    return { results: [] };
  },
);

// Stream out
export const streamEvents = api.streamOut<
  { channel: string },
  { event: string; data: string }
>(
  { path: "/api/events/:channel", expose: true },
  async ({ channel }, stream) => {
    // streaming logic
  },
);

// Stream in
export const uploadChunks = api.streamIn<
  { uploadId: string; chunk: string },
  { received: number }
>({ path: "/api/uploads", expose: true }, async (stream) => {
  // streaming logic
});

// Stream in/out
export const chat = api.streamInOut<
  { message: string; sessionId?: string },
  { reply: string; done: boolean }
>({ path: "/api/chat", expose: true }, async (stream) => {
  // streaming logic
});

// POST with optional fields and union types
export const processData = api(
  { method: "POST", path: "/api/process" },
  async (req: {
    data: string;
    format?: string;
    callback: string | undefined;
  }) => {
    return { processed: true };
  },
);

// DELETE endpoint
export const deleteItem = api(
  { method: "DELETE", path: "/api/items/:id" },
  async (req: { id: string }) => {
    return { deleted: true };
  },
);

// PATCH endpoint with array and nested object types
export const patchItem = api(
  { method: "PATCH", path: "/api/items/:id" },
  async (req: { id: string; tags: string[]; metadata: { key: string } }) => {
    return { patched: true };
  },
);

// Named type reference (can't resolve without LSP)
interface SearchParams {
  query: string;
  limit: number;
}

export const search = api(
  { method: "GET", path: "/api/search" },
  async (req: SearchParams) => {
    return { results: [] };
  },
);
