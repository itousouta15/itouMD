/**
 * itouMD built-in AI quota proxy.
 *
 * Forwards OpenAI-compatible chat completions from the itouMD app to
 * OpenCode Zen's free models (https://opencode.ai/zen). The Zen API key
 * lives in the Worker secret `ZEN_API_KEY` — never in the app or the repo.
 *
 * Deploy:
 *   npx wrangler login
 *   npx wrangler deploy
 *   npx wrangler secret put ZEN_API_KEY
 *   (bind https://llm.itousouta.me to this Worker in the dashboard or
 *    via the `routes` in wrangler.toml)
 */

const ZEN_ENDPOINT = 'https://opencode.ai/zen/v1/chat/completions';

// Only free models may be requested through this proxy — paid models would
// silently burn the account's credits.
const ALLOWED_MODELS = new Set([
  'deepseek-v4-flash-free',
  'ling-3.0-flash-free',
  'nemotron-3-ultra-free',
  'mimo-v2.5-free',
]);

// Fallback model used when Zen is down/rate-limited: Cloudflare Workers AI
// (free tier, no external key). Qwen3 handles Traditional Chinese well.
const FALLBACK_AI_MODEL = '@cf/qwen/qwen3-30b-a3b-fp8';

// Simple per-IP sliding window: at most 10 requests per 10 seconds. Kept in
// module scope; a cold start just resets the window.
const RATE_LIMIT_MAX = 10;
const RATE_LIMIT_WINDOW_MS = 10_000;
const rateBuckets = new Map();

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }
    if (request.method !== 'POST') {
      return json({ error: { message: '只支援 POST' } }, 405);
    }

    const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
    if (!rateLimited(ip)) {
      return json(
        { error: { message: '請求太頻繁了，稍後再試 (´;ω;`)' } },
        429,
      );
    }

    const zenKey = env.ZEN_API_KEY;
    if (!zenKey) {
      return json(
        { error: { message: '伺服器尚未設定 API Key (´;ω;`)' } },
        500,
      );
    }

    let body;
    try {
      body = await request.json();
    } catch (_) {
      return json({ error: { message: '請求格式錯誤' } }, 400);
    }

    const model = body?.model;
    if (typeof model !== 'string' || !ALLOWED_MODELS.has(model)) {
      return json(
        { error: { message: `不允許的模型：${model ?? '(空)'}` } },
        400,
      );
    }

    try {
      const upstream = await fetch(ZEN_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${zenKey}`,
        },
        body: JSON.stringify(body),
      });

      if (upstream.status < 400) {
        const contentType = upstream.headers.get('content-type') ?? '';
        const responseBody = await upstream.arrayBuffer();
        return new Response(responseBody, {
          status: upstream.status,
          headers: {
            'Content-Type': contentType,
            ...corsHeaders(),
          },
        });
      }

      // Zen failed (rate limit, outage, ...) — fall back to Workers AI so
      // the built-in quota keeps working.
      const fallback = await fallbackWorkersAI(env, body);
      if (fallback) return fallback;
      return json({ error: { message: 'AI 服務暫時出問題 (´;ω;`)' } }, 502);
    } catch (_) {
      const fallback = await fallbackWorkersAI(env, body);
      if (fallback) return fallback;
      return json({ error: { message: 'AI 服務暫時出問題 (´;ω;`)' } }, 502);
    }
  },
};

async function fallbackWorkersAI(env, body) {
  try {
    const messages = Array.isArray(body?.messages)
      ? body.messages
      : [{ role: 'user', content: '你好' }];
    const result = await env.AI.run(FALLBACK_AI_MODEL, { messages });
    const content = result?.response ?? result?.output_text;
    if (!content || typeof content !== 'string') return null;
    const model = body?.model ?? FALLBACK_AI_MODEL;
    if (body?.stream === true) {
      // The client always parses SSE — wrap the single completion in one
      // data chunk plus the [DONE] terminator.
      const payload = {
        id: 'chatcmpl-workers-ai',
        object: 'chat.completion.chunk',
        created: Math.floor(Date.now() / 1000),
        model,
        choices: [
          { index: 0, delta: { role: 'assistant', content }, finish_reason: 'stop' },
        ],
      };
      const sse =
        `data: ${JSON.stringify(payload)}\n\n` + 'data: [DONE]\n\n';
      return new Response(sse, {
        status: 200,
        headers: {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          ...corsHeaders(),
        },
      });
    }
    return json(
      {
        id: 'chatcmpl-workers-ai',
        object: 'chat.completion',
        created: Math.floor(Date.now() / 1000),
        model,
        choices: [
          {
            index: 0,
            message: { role: 'assistant', content },
            finish_reason: 'stop',
          },
        ],
        usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
      },
      200,
    );
  } catch (_) {
    return null;
  }
}

function rateLimited(ip) {
  const now = Date.now();
  const hits = (rateBuckets.get(ip) ?? []).filter(
    (t) => now - t < RATE_LIMIT_WINDOW_MS,
  );
  if (hits.length >= RATE_LIMIT_MAX) {
    rateBuckets.set(ip, hits);
    return false;
  }
  hits.push(now);
  rateBuckets.set(ip, hits);
  return true;
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };
}

function json(payload, status) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders() },
  });
}
