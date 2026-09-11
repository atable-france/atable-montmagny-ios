import { NextResponse } from "next/server";
import { cityBySlug } from "@/lib/cities";
import { resolveDiscoveredCity } from "@/lib/discovery";
export const runtime = "nodejs";
export const maxDuration = 60;
export async function GET(request: Request) {
  const slug = new URL(request.url).searchParams.get("slug") ?? "";
  try {
    const city = cityBySlug(slug) ?? await resolveDiscoveredCity(slug);
    return NextResponse.json(city ?? { error: "Source introuvable. Relancez une recherche." }, { status: city ? 200 : 404 });
  } catch { return NextResponse.json({ error: "Source temporairement indisponible." }, { status: 503 }); }
}
