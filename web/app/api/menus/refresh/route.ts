import { NextResponse } from "next/server";
import { cities } from "@/lib/cities";
import { mondayOf } from "@/lib/date";
import { fetchMenus } from "@/lib/menus";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (secret && request.headers.get("authorization") !== `Bearer ${secret}`) return new NextResponse("Unauthorized", { status: 401 });
  const week = mondayOf();
  const results = await Promise.allSettled(cities.map((city) => fetchMenus(city.slug, week)));
  return NextResponse.json({ week, cities: cities.map((city, index) => ({ city: city.slug, ok: results[index].status === "fulfilled" })) });
}
