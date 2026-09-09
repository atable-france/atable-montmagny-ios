import { cityBySlug } from "./cities";
import { fetchArgenteuil } from "./argenteuil";
import { fetchFoodi } from "./foodi";

export async function fetchMenus(citySlug: string, weekStart: string, level: "elementary" | "nursery" = "elementary") {
  const city = cityBySlug(citySlug);
  if (!city) throw new Error("Ville non prise en charge.");
  return city.source.kind === "foodi" ? fetchFoodi(city, weekStart) : fetchArgenteuil(city, weekStart, level);
}
