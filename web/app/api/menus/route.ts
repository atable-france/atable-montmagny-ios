import { NextResponse } from "next/server";
import { mondayOf, weekDates } from "@/lib/date";
import { fetchMenus } from "@/lib/menus";

export const runtime = "nodejs";
export const maxDuration = 60;

export async function GET(request: Request) {
  const url = new URL(request.url);
  const city = url.searchParams.get("city") ?? "montmagny";
  const week = url.searchParams.get("week") ?? mondayOf();
  const level = url.searchParams.get("level") === "nursery" ? "nursery" : "elementary";
  try { weekDates(week); } catch { return NextResponse.json({ error: "La semaine doit commencer un lundi valide." }, { status: 400 }); }
  try {
    return NextResponse.json(await fetchMenus(city, week, level), {
      headers: { "Cache-Control": "s-maxage=1800, stale-while-revalidate=86400" },
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Menus indisponibles." }, { status: 502 });
  }
}
