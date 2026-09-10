import { cityBySlug } from "./cities";
import { fetchFoodi } from "./foodi";

export async function fetchMenus(citySlug: string, weekStart: string, level: "elementary" | "nursery" = "elementary") {
  const city = cityBySlug(citySlug);
  if (!city) throw new Error("Ville non prise en charge.");
  if (city.source.kind === "foodi") return fetchFoodi(city, weekStart);
  const { fetchArgenteuil } = await import("./argenteuil");
  return fetchArgenteuil(city, weekStart, level);
}
