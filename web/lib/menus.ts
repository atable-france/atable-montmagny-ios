import { cityBySlug } from "./cities";
import { fetchFoodi } from "./foodi";
import { resolveDiscoveredCity } from "./discovery";
import { weekDates } from "./date";
import type { WeekMenu } from "./types";
export async function fetchMenus(citySlug: string, weekStart: string, level: "elementary" | "nursery" = "elementary") {
  const city = cityBySlug(citySlug) ?? await resolveDiscoveredCity(citySlug);
  if (!city) throw new Error("Ville non prise en charge.");
  if (city.source.kind === "foodi") return fetchFoodi(city, weekStart);
  if (city.source.kind === "municipal") return {
    city: city.slug, cityName: city.name, postalCode: city.postalCode, weekStart,
    fetchedAt: new Date().toISOString(), sourceName: "Site officiel de la mairie",
    sourceUrl: city.source.municipalUrl, documents: city.source.links,
    accessCode: city.source.accessCode, requiresAccount: city.source.requiresAccount,
    days: weekDates(weekStart).map(date => ({ date, items: [] })),
  } satisfies WeekMenu;
  const { fetchArgenteuil } = await import("./argenteuil");
  return fetchArgenteuil(city, weekStart, level);
}
