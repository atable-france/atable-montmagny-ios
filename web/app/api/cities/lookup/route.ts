import { NextResponse } from "next/server";
import { cities, cityByLocation, normalizeCityName } from "@/lib/cities";

type Commune = {
  nom: string;
  codesPostaux?: string[];
};

export const runtime = "nodejs";

export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const name = (params.get("name") ?? "").trim();
  const postalCode = (params.get("postalCode") ?? "").replace(/\s/g, "");

  if (name.length < 2 || !/^\d{5}$/.test(postalCode)) {
    return NextResponse.json(
      { error: "Indiquez une ville et un code postal français à 5 chiffres." },
      { status: 400 },
    );
  }

  const registered = cityByLocation(name, postalCode);
  if (registered) {
    return NextResponse.json({
      supported: true,
      commune: { name: registered.name, postalCode: registered.postalCode },
      city: publicCity(registered),
    });
  }

  try {
    const endpoint = new URL("https://geo.api.gouv.fr/communes");
    endpoint.searchParams.set("codePostal", postalCode);
    endpoint.searchParams.set("fields", "nom,codesPostaux");
    endpoint.searchParams.set("format", "json");
    const response = await fetch(endpoint, { next: { revalidate: 86_400 } });
    if (!response.ok) throw new Error(`geo.api.gouv.fr: ${response.status}`);
    const communes = (await response.json()) as Commune[];
    const commune = communes.find((item) => normalizeCityName(item.nom) === normalizeCityName(name));

    if (!commune) {
      return NextResponse.json({
        supported: false,
        commune: null,
        suggestions: communes.slice(0, 5).map((item) => item.nom),
        error: communes.length
          ? "Le nom de la ville ne correspond pas à ce code postal."
          : "Ce code postal n’a pas été reconnu.",
      });
    }

    const canonical = cityByLocation(commune.nom, postalCode);
    return NextResponse.json({
      supported: Boolean(canonical),
      commune: { name: commune.nom, postalCode },
      city: canonical ? publicCity(canonical) : null,
      availableCities: cities.map(publicCity),
    });
  } catch {
    return NextResponse.json({
      supported: false,
      commune: { name, postalCode },
      city: null,
      availableCities: cities.map(publicCity),
      warning: "La vérification de la commune est momentanément indisponible.",
    });
  }
}

function publicCity(city: (typeof cities)[number]) {
  return {
    slug: city.slug,
    name: city.name,
    postalCode: city.postalCode,
    schoolLevels: city.source.kind === "argenteuil-pdf" ? ["elementary", "nursery"] : ["elementary"],
  };
}
