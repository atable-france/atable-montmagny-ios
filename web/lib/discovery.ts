import { unstable_cache } from "next/cache";
import { type City, normalizeCityName, cityByLocation } from "./cities";
import { pageLinks, publicPage } from "./public-page";

type Commune = { code: string; nom: string; codesPostaux: string[] };
async function json(url: string, init?: RequestInit) {
  const response = await fetch(url, { ...init, signal: AbortSignal.timeout(8000), next: { revalidate: 21600 } });
  if (!response.ok) throw new Error("Source temporairement indisponible.");
  return response.json();
}
async function graphql(query: string, variables: Record<string, unknown>) {
  const result = await json("https://api.foodi.fr/graphql", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ query, variables }) });
  if (result.errors?.length) throw new Error("Recherche Foodi indisponible.");
  return result.data;
}

async function foodi(commune: Commune, postalCode: string): Promise<City[]> {
  const data = await graphql(`query($search: String!) { nearHoldings(search: $search, first: 50) { edges { node { holding { id name foodi address { zip } zones { numericId name status } } } } } }`, { search: commune.nom });
  const holdings = data.nearHoldings.edges.map((e: any) => e.node.holding).filter((h: any) => h.foodi && h.address?.zip === postalCode).slice(0, 4);
  const candidates: City[] = [];
  for (const holding of holdings) {
    for (const zone of holding.zones.filter((z: any) => z.status === "VISIBLE").slice(0, 3)) {
      const points = await graphql(`query { list(type: "Pos", querySearch: [{key: "idZone", value: "${Number(zone.numericId)}"}]) { edges { node { ... on Pos { id name zone { holding { id } } } } } } }`, {});
      for (const { node: point } of points.list.edges) {
        if (point.zone?.holding?.id !== holding.id || !/scolaire|ecole|elementaire|maternell|college|lycee|primaire/.test(normalizeCityName(point.name))) continue;
        const number = Buffer.from(point.id, "base64").toString().match(/^Pos:(\d+)$/)?.[1];
        if (!number) continue;
        candidates.push({ slug: `fr-${commune.code}-${postalCode}-foodi-${number}`, name: commune.nom, postalCode, restaurantName: point.name,
          source: { kind: "foodi", posId: point.id, municipalUrl: "https://www.foodi.fr/" } });
      }
    }
  }
  return candidates;
}

async function municipal(commune: Commune, postalCode: string): Promise<City | null> {
  const endpoint = new URL("https://api-lannuaire.service-public.gouv.fr/api/explore/v2.1/catalog/datasets/api-lannuaire-administration/records");
  endpoint.searchParams.set("where", `code_insee_commune LIKE "${commune.code}" AND nom LIKE "Mairie%"`); endpoint.searchParams.set("limit", "20");
  const records = await json(endpoint.href);
  const mairie = records.results.find((r: any) => JSON.parse(r.pivot || "[]").some((p: any) => p.type_service_local === "mairie" && p.code_insee_commune.includes(commune.code)));
  const site = mairie && JSON.parse(mairie.site_internet || "[]")[0]?.valeur;
  if (!site) return null;
  const home = await publicPage(site);
  const homeLinks = pageLinks(home.html, home.url);
  const score = (link: { title: string; url: string }) => {
    const s = normalizeCityName(`${link.title} ${new URL(link.url).pathname}`);
    return /restauration scolaire|menu.*cantine|cantine.*menu/.test(s) ? 3 : /cantine|restauration/.test(s) ? 2 : /scolaire|enfance/.test(s) ? 1 : 0;
  };
  const pages = homeLinks.filter((l) => new URL(l.url).origin === new URL(home.url).origin && score(l) > 0 && !/\.pdf$/i.test(l.url)).sort((a, b) => score(b) - score(a)).slice(0, 3);
  for (const link of pages) {
    const page = await publicPage(link.url);
    const links = pageLinks(page.html, page.url);
    const provider = links.find((l) => /(^|\.)(clicetmiam\.fr|foodi\.fr|bonapp\.elior\.com|so-happy\.fr)$/.test(new URL(l.url).hostname));
    const documents = links.filter((l) => /menu/i.test(l.title + " " + new URL(l.url).pathname) && /\.pdf(?:\?|$)/i.test(l.url)).slice(0, 12);
    if (!provider && !documents.length) continue;
    const plain = page.html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");
    const accessCode = plain.match(/code [ée]tablissement.{0,100}?(?:est|:)[\s:]*([A-Z0-9]{2,12})\b/)?.[1];
    return { slug: `fr-${commune.code}-${postalCode}`, name: commune.nom, postalCode,
      source: { kind: "municipal", municipalUrl: page.url, links: provider ? [provider, ...documents] : documents,
        accessCode, requiresAccount: provider ? new URL(provider.url).hostname.endsWith("clicetmiam.fr") : false } };
  }
  return { slug: `fr-${commune.code}-${postalCode}`, name: commune.nom, postalCode,
    source: { kind: "municipal", municipalUrl: pages[0]?.url || home.url, links: [] } };
}

export const discoverCommune = unstable_cache(async (code: string, postalCode: string) => {
  if (!/^[0-9A-B]{5}$/.test(code) || !/^\d{5}$/.test(postalCode)) throw new Error("Commune invalide.");
  const commune = await json(`https://geo.api.gouv.fr/communes/${code}?fields=nom,code,codesPostaux`) as Commune;
  if (!commune.codesPostaux.includes(postalCode)) throw new Error("Code postal incohérent.");
  const known = cityByLocation(commune.nom, postalCode);
  if (known) return { candidates: [known], warnings: [] as string[] };
  const warnings: string[] = [];
  try { const candidates = await foodi(commune, postalCode); if (candidates.length) return { candidates, warnings }; }
  catch (error) { console.warn("Foodi discovery failed", error); warnings.push("Foodi n’a pas pu être interrogé pour le moment."); }
  try { const source = await municipal(commune, postalCode); return { candidates: source ? [source] : [], warnings }; }
  catch (error) { console.warn("Municipal discovery failed", error); warnings.push("Le site municipal n’a pas pu être lu automatiquement."); return { candidates: [], warnings }; }
}, ["city-discovery-v3"], { revalidate: 21600 });

export async function resolveDiscoveredCity(slug: string) {
  const match = slug.match(/^fr-([0-9A-B]{5})-(\d{5})(?:-foodi-\d+)?$/);
  if (!match) return undefined;
  return (await discoverCommune(match[1], match[2])).candidates.find((c) => c.slug === slug);
}
