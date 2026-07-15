#!/usr/bin/env node
import http from "node:http";

const host = process.env.SEARXNG_MCP_HOST || "127.0.0.1";
const port = Number.parseInt(process.env.SEARXNG_MCP_PORT || "8765", 10);
const searxngUrl = process.env.SEARXNG_URL || "http://127.0.0.1:8080";
const requestTimeoutMs = Number.parseInt(process.env.SEARXNG_TIMEOUT_MS || "30000", 10);
const allowedOrigins = new Set(
  (process.env.SEARXNG_MCP_ALLOWED_ORIGINS ||
    "http://127.0.0.1:8081,http://localhost:8081")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
);

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error(`Invalid SEARXNG_MCP_PORT: ${process.env.SEARXNG_MCP_PORT}`);
}

const tool = {
  name: "web_search",
  title: "SearXNG Web Search",
  description:
    "Search the public web through the user's private local SearXNG instance. Returns titles, URLs and result snippets.",
  inputSchema: {
    type: "object",
    properties: {
      query: { type: "string", description: "The web search query." },
      limit: {
        type: "integer",
        minimum: 1,
        maximum: 10,
        default: 5,
        description: "Maximum number of results to return.",
      },
      language: {
        type: "string",
        description: "Optional SearXNG language code, for example en, es or all.",
      },
      time_range: {
        type: "string",
        enum: ["day", "month", "year"],
        description: "Optional recency filter.",
      },
    },
    required: ["query"],
    additionalProperties: false,
  },
};

function corsHeaders(req) {
  const origin = req.headers.origin;
  const headers = {
    "Access-Control-Allow-Headers":
      "content-type, accept, authorization, mcp-protocol-version, mcp-session-id",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Expose-Headers": "mcp-session-id",
    Vary: "Origin",
  };
  if (origin && allowedOrigins.has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function sendJson(req, res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {
    ...corsHeaders(req),
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

function rpcResult(id, result) {
  return { jsonrpc: "2.0", id, result };
}

function rpcError(id, code, message, data) {
  return {
    jsonrpc: "2.0",
    id: id ?? null,
    error: { code, message, ...(data === undefined ? {} : { data }) },
  };
}

function cleanText(value, maxLength = 700) {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  return text.length <= maxLength ? text : `${text.slice(0, maxLength - 1)}…`;
}

async function searchWeb(args = {}) {
  const query = typeof args.query === "string" ? args.query.trim() : "";
  if (!query) throw new Error("query must be a non-empty string");

  const requestedLimit = Number.isInteger(args.limit) ? args.limit : 5;
  const limit = Math.min(10, Math.max(1, requestedLimit));
  const url = new URL("/search", searxngUrl);
  url.searchParams.set("q", query);
  url.searchParams.set("format", "json");
  if (typeof args.language === "string" && args.language.trim()) {
    url.searchParams.set("language", args.language.trim());
  }
  if (["day", "month", "year"].includes(args.time_range)) {
    url.searchParams.set("time_range", args.time_range);
  }

  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(requestTimeoutMs),
  });
  if (!response.ok) throw new Error(`SearXNG returned HTTP ${response.status}`);
  const payload = await response.json();
  const results = (Array.isArray(payload.results) ? payload.results : [])
    .slice(0, limit)
    .map((result) => ({
      title: cleanText(result.title, 240) || "Untitled result",
      url: String(result.url || ""),
      snippet: cleanText(result.content),
      engines: Array.isArray(result.engines) ? result.engines.slice(0, 8) : [],
      publishedDate: result.publishedDate || result.pubdate || null,
    }))
    .filter((result) => result.url);

  const text = results.length
    ? results
        .map(
          (result, index) =>
            `${index + 1}. ${result.title}\n${result.url}${result.snippet ? `\n${result.snippet}` : ""}`,
        )
        .join("\n\n")
    : `No results found for: ${query}`;

  return {
    content: [{ type: "text", text }],
    structuredContent: { query, results },
  };
}

async function handleRpc(message) {
  if (!message || message.jsonrpc !== "2.0" || typeof message.method !== "string") {
    return rpcError(message?.id, -32600, "Invalid Request");
  }

  const { id, method, params } = message;
  if (id === undefined) return null;

  switch (method) {
    case "initialize":
      return rpcResult(id, {
        protocolVersion: params?.protocolVersion || "2025-03-26",
        capabilities: { tools: { listChanged: false } },
        serverInfo: {
          name: "local-searxng",
          title: "Local SearXNG",
          version: "1.0.0",
        },
      });
    case "ping":
      return rpcResult(id, {});
    case "tools/list":
      return rpcResult(id, { tools: [tool] });
    case "tools/call":
      if (params?.name !== tool.name) return rpcError(id, -32602, `Unknown tool: ${params?.name}`);
      try {
        return rpcResult(id, await searchWeb(params.arguments));
      } catch (error) {
        return rpcResult(id, {
          content: [{ type: "text", text: `SearXNG search failed: ${error.message}` }],
          isError: true,
        });
      }
    default:
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    res.writeHead(204, corsHeaders(req));
    res.end();
    return;
  }

  const requestUrl = new URL(req.url || "/", `http://${req.headers.host || host}`);
  if (req.method === "GET" && requestUrl.pathname === "/health") {
    sendJson(req, res, 200, { status: "ok", searxng: searxngUrl });
    return;
  }
  if (requestUrl.pathname !== "/mcp") {
    sendJson(req, res, 404, { error: "not found" });
    return;
  }
  if (req.method === "GET") {
    sendJson(req, res, 405, { error: "SSE stream not enabled; use Streamable HTTP POST" });
    return;
  }
  if (req.method === "DELETE") {
    sendJson(req, res, 200, {});
    return;
  }
  if (req.method !== "POST") {
    sendJson(req, res, 405, { error: "method not allowed" });
    return;
  }

  let body = "";
  for await (const chunk of req) {
    body += chunk;
    if (body.length > 1024 * 1024) {
      sendJson(req, res, 413, rpcError(null, -32600, "Request too large"));
      return;
    }
  }

  let payload;
  try {
    payload = JSON.parse(body);
  } catch {
    sendJson(req, res, 400, rpcError(null, -32700, "Parse error"));
    return;
  }

  const messages = Array.isArray(payload) ? payload : [payload];
  const responses = (await Promise.all(messages.map(handleRpc))).filter(Boolean);
  if (responses.length === 0) {
    res.writeHead(202, corsHeaders(req));
    res.end();
    return;
  }
  sendJson(req, res, 200, Array.isArray(payload) ? responses : responses[0]);
});

server.listen(port, host, () => {
  console.log(`SearXNG MCP listening at http://${host}:${port}/mcp`);
  console.log(`SearXNG upstream: ${searxngUrl}`);
});

function shutdown() {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 2000).unref();
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
