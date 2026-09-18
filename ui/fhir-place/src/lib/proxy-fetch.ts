import "server-only";

import { ProxyAgent, fetch as undiciFetch } from "undici";
import type { RequestInit } from "undici";

let proxyAgent: ProxyAgent | undefined;
let proxyAgentUrl: string | undefined;

function validateOutboundUrl(rawUrl: string): URL {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new Error(`Invalid URL: ${rawUrl}`);
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error(`Unsupported URL protocol: ${parsed.protocol}`);
  }

  return parsed;
}

function getProxyUrl(targetProtocol: string): string | undefined {
  // Prefer the proxy matching the target protocol, then fall back to the
  // other protocol and to a protocol-agnostic ALL_PROXY. This mirrors how
  // most tooling interprets HTTP_PROXY/HTTPS_PROXY.
  if (targetProtocol === "https:") {
    return (
      process.env.HTTPS_PROXY ??
      process.env.https_proxy ??
      process.env.HTTP_PROXY ??
      process.env.http_proxy ??
      process.env.ALL_PROXY ??
      process.env.all_proxy
    );
  }

  return (
    process.env.HTTP_PROXY ??
    process.env.http_proxy ??
    process.env.HTTPS_PROXY ??
    process.env.https_proxy ??
    process.env.ALL_PROXY ??
    process.env.all_proxy
  );
}

function isLoopbackHost(host: string): boolean {
  const lower = host.toLowerCase();
  return (
    lower === "localhost" ||
    lower === "127.0.0.1" ||
    lower === "[::1]" ||
    lower === "::1"
  );
}

function shouldBypassProxy(host: string, port: string, noProxy: string): boolean {
  const entries = noProxy
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);

  if (entries.includes("*")) {
    return true;
  }

  const hostLower = host.toLowerCase();
  const hostWithPort = port ? `${hostLower}:${port}` : hostLower;

  for (const entry of entries) {
    const entryLower = entry.toLowerCase();

    if (entryLower.includes(":")) {
      if (hostWithPort === entryLower) {
        return true;
      }
      continue;
    }

    if (entryLower === "*") {
      return true;
    }

    const normalizedEntry = entryLower.startsWith(".")
      ? entryLower.slice(1)
      : entryLower;

    if (
      hostLower === normalizedEntry ||
      hostLower.endsWith(`.${normalizedEntry}`)
    ) {
      return true;
    }
  }

  return false;
}

export async function proxyFetch(
  url: string,
  init?: RequestInit
): Promise<Response> {
  const parsed = validateOutboundUrl(url);
  const proxyUrl = getProxyUrl(parsed.protocol);

  if (!proxyUrl) {
    return fetch(parsed.toString(), init as globalThis.RequestInit);
  }

  if (isLoopbackHost(parsed.hostname)) {
    return fetch(parsed.toString(), init as globalThis.RequestInit);
  }

  const noProxy = process.env.NO_PROXY ?? process.env.no_proxy;
  if (noProxy && shouldBypassProxy(parsed.hostname, parsed.port, noProxy)) {
    return fetch(parsed.toString(), init as globalThis.RequestInit);
  }

  if (!proxyAgent || proxyAgentUrl !== proxyUrl) {
    proxyAgentUrl = proxyUrl;
    proxyAgent = new ProxyAgent(proxyUrl);
  }

  return undiciFetch(parsed.toString(), {
    ...init,
    dispatcher: proxyAgent,
  }) as unknown as Response;
}
