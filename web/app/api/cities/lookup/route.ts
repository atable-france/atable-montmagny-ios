import { NextResponse } from "next/server";
import { cityByLocation, normalizeCityName } from "@/lib/cities";
import { discoverCommune } from "@/lib/discovery";
export const runtime = "nodejs";
export const maxDuration = 60;
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const name = (params.get("name") ?? "").trim();
  const postalCode = (params.get("postalCode") ?? "").trim();
  if (name.length < 2 || name.length > 100 || !/^\d{5}$/.test(postalCode)) return NextResponse.json({ error: "Indiquez une ville et un code postal français à 5 chiffres." }, { status: 400 });
  const known = cityByLocation(name, postalCode);
  if (known) return NextResponse.json({ candidates: [known], commune: { name: known.name, postalCode }, warnings: [] });
  try {
    const response = await fetch(`https://geo.api.gouv.fr/communes?codePostal=${postalCode}&fields=nom,code,codesPostaux`, { next: { revalidate: 86400 }, signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error("Annuaire indisponible.");
    const communes = await response.json() as { nom: string; code: string }[];
    const commune = communes.find(c => normalizeCityName(c.nom) === normalizeCityName(name));
    if (!commune) return NextResponse.json({ candidates: [], commune: null, suggestions: communes.slice(0, 5).map(c => c.nom), error: "La ville ne correspond pas à ce code postal." });
    return NextResponse.json({ ...await discoverCommune(commune.code, postalCode), commune: { name: commune.nom, postalCode } });
  } catch {
    return NextResponse.json({ error: "La recherche est momentanément indisponible. Réessayez dans quelques instants." }, { status: 503 });
  }
}
