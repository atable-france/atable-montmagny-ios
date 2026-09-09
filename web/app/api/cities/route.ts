import { NextResponse } from "next/server";
import { cities } from "@/lib/cities";

export function GET() {
  return NextResponse.json(cities.map(({ slug, name, postalCode, source }) => ({
    slug, name, postalCode, schoolLevels: source.kind === "argenteuil-pdf" ? ["elementary", "nursery"] : ["elementary"],
  })));
}
