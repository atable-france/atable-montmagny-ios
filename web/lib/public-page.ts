import { lookup } from "node:dns/promises";
import { request } from "node:https";
import { isIP } from "node:net";

// Municipal sites are external input. Resolve and pin a public IPv4 on every hop.
export function publicIPv4(ip: string) {
  if (isIP(ip) !== 4) return false;
  const [a, b] = ip.split(".").map(Number);
  return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
    (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && [0, 168].includes(b)) || (a === 100 && b >= 64 && b <= 127) ||
    (a === 198 && [18, 19, 51].includes(b)) || (a === 203 && b === 0));
}

export async function publicPage(value: string, hops = 0): Promise<{ url: string; html: string }> {
  const url = new URL(value);
  if (url.protocol === "http:") url.protocol = "https:";
  if (url.protocol !== "https:" || url.username || url.password || (url.port && url.port !== "443") || hops > 3) throw new Error("Adresse non autorisée.");
  const addresses = await lookup(url.hostname, { family: 4, all: true });
  if (!addresses.length || addresses.some(({ address }) => !publicIPv4(address))) throw new Error("Adresse non publique.");
  const result = await new Promise<{ location?: string; html: string }>((resolve, reject) => {
    const req = request(url, { headers: { "User-Agent": "MaFabuleuseCantine/1.0 (public school menu discovery)", "Accept": "text/html" },
      lookup: (_host, options, callback) => {
        if (options?.all) (callback as unknown as (error: null, values: { address: string; family: number }[]) => void)(null, addresses);
        else (callback as unknown as (error: null, address: string, family: number) => void)(null, addresses[0].address, 4);
      },
    }, (res) => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode ?? 0)) { res.resume(); resolve({ location: res.headers.location, html: "" }); return; }
      if (res.statusCode !== 200 || !/text\/html/i.test(res.headers["content-type"] ?? "")) { res.resume(); reject(new Error("Page inaccessible.")); return; }
      const chunks: Buffer[] = []; let size = 0;
      res.on("data", (chunk: Buffer) => { size += chunk.length; if (size > 1_500_000) req.destroy(new Error("Page trop volumineuse.")); else chunks.push(chunk); });
      res.on("end", () => resolve({ html: Buffer.concat(chunks).toString("utf8") }));
      res.on("error", reject);
    });
    const timer = setTimeout(() => req.destroy(new Error("Délai de lecture dépassé.")), 6000);
    req.on("close", () => clearTimeout(timer)); req.on("error", reject); req.end();
  });
  return result.location ? publicPage(new URL(result.location, url).href, hops + 1) : { url: url.href, html: result.html };
}

export function pageLinks(html: string, base: string) {
  const seen = new Set<string>();
  return [...html.matchAll(/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)].flatMap((m) => {
    try {
      const url = new URL(m[1].replace(/&amp;/g, "&"), base); url.hash = "";
      const title = m[2].replace(/<[^>]*>/g, " ").replace(/&nbsp;|&#160;/g, " ").replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
      if (!["https:", "http:"].includes(url.protocol) || url.username || url.password || seen.has(url.href)) return [];
      seen.add(url.href); return [{ url: url.href, title: title || url.pathname.split("/").pop() || "Consulter" }];
    } catch { return []; }
  });
}
