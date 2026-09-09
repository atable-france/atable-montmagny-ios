import { classifyDiet } from "./diet";
import { weekDates } from "./date";
import type { City } from "./cities";
import type { MenuItem, WeekMenu } from "./types";

const endpoint = "https://api.foodi.fr/graphql";

function groupOf(id?: string): MenuItem["group"] {
  if (!id) return "other";
  try {
    const value = Number(Buffer.from(id, "base64").toString().split(":").at(-1));
    return ({ 529: "starter", 530: "main", 531: "dessert", 533: "dairy", 534: "side" } as const)[value] ?? "other";
  } catch { return "other"; }
}

export async function fetchFoodi(city: City, weekStart: string): Promise<WeekMenu> {
  if (city.source.kind !== "foodi") throw new Error("Source Foodi absente.");
  const dates = weekDates(weekStart);
  const fields = dates.map((date, index) => `jour${index}: menus(date: \"${date}\") { day elements { id label dish { id dishGroup { id } } } }`).join("\n");
  const query = `query ATableMenus($id: ID!) { getPos(id: $id) { id name ${fields} } }`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ operationName: "ATableMenus", query, variables: { id: city.source.posId } }),
    next: { revalidate: 1800 },
  });
  if (!response.ok) throw new Error(`Foodi indisponible (${response.status}).`);
  const json = await response.json();
  if (json.errors?.length || json.data?.getPos?.id !== city.source.posId) throw new Error("Réponse Foodi invalide.");
  const pos = json.data.getPos;
  return {
    city: city.slug, cityName: city.name, postalCode: city.postalCode, weekStart,
    fetchedAt: new Date().toISOString(), sourceName: "Foodi", sourceUrl: city.source.municipalUrl,
    days: dates.map((date, index) => ({
      date,
      items: (pos[`jour${index}`] ?? []).flatMap((menu: { elements?: any[] }) => menu.elements ?? []).map((item: any) => ({
        id: item.id, label: item.label, group: groupOf(item.dish?.id), diet: classifyDiet(item.label),
      })),
    })),
  };
}
