import { createHash } from "node:crypto";
import { getDocument } from "pdfjs-dist/legacy/build/pdf.mjs";
import { classifyDiet } from "./diet";
import { weekDates } from "./date";
import type { City } from "./cities";
import type { MenuDay, MenuItem, WeekMenu } from "./types";

type PositionedText = { text: string; x: number; y: number };
const dayNames = ["LUNDI", "MARDI", "MERCREDI", "JEUDI", "VENDREDI"];
const months: Record<string, number> = {
  JANVIER: 1, FEVRIER: 2, "FÉVRIER": 2, MARS: 3, AVRIL: 4, MAI: 5, JUIN: 6,
  JUILLET: 7, AOUT: 8, "AOÛT": 8, SEPTEMBRE: 9, OCTOBRE: 10, NOVEMBRE: 11, DECEMBRE: 12, "DÉCEMBRE": 12,
};

function pad(value: number) { return String(value).padStart(2, "0"); }

function startDates(items: PositionedText[], year: number) {
  const markers = items.filter((item) => item.x < 180 && item.text === "DU").sort((a, b) => b.y - a.y);
  return markers.flatMap((marker) => {
    const below = items.filter((item) => item.x < 180 && item.y < marker.y && item.y > marker.y - 90).sort((a, b) => b.y - a.y);
    const day = below.find((item) => /^\d{1,2}$/.test(item.text));
    const month = below.find((item) => months[item.text] != null);
    if (!day || !month || !Number.isInteger(year)) return [];
    const value = `${year}-${pad(months[month.text])}-${pad(Number(day.text))}`;
    return new Date(`${value}T00:00:00Z`).getUTCDay() === 1 ? [value] : [];
  });
}

function joinLines(items: PositionedText[]) {
  const rows: PositionedText[][] = [];
  for (const item of [...items].sort((a, b) => b.y - a.y || a.x - b.x)) {
    const row = rows.find((candidate) => Math.abs(candidate[0].y - item.y) < 2.2);
    if (row) row.push(item); else rows.push([item]);
  }
  return rows.map((row) => row.sort((a, b) => a.x - b.x).map((item) => item.text).join(" ").replace(/\s+/g, " ").trim());
}

function inferGroup(label: string, index: number, total: number): MenuItem["group"] {
  const value = label.toLowerCase();
  if (/fromage|yaourt|petit suisse|camembert|cantal|brie|tomme|saint-nectaire|faisselle/.test(value)) return "dairy";
  if (/fruit|banane|raisin|mirabelle|beignet|gaufre|gâteau|gateau|tarte|compote|crème dessert|creme dessert/.test(value)) return "dessert";
  if (/salade|crudité|crudite|betterave|carotte râpée|carotte rapee|concombre|radis/.test(value)) return "starter";
  if (classifyDiet(label) !== "unknown") return "main";
  if (/poêlée|poelee|purée|puree|riz|pâte|pate|penne|semoule|haricot|chou-fleur|légume|legume|épinard|epinard|blettes|polenta/.test(value)) return "side";
  return index === 1 || (index === 0 && total < 4) ? "main" : "other";
}

async function parsePdf(buffer: ArrayBuffer) {
  const pdf = await getDocument({ data: new Uint8Array(buffer), useWorkerFetch: false }).promise;
  const parsed = new Map<string, MenuItem[]>();
  for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
    const page = await pdf.getPage(pageNumber);
    const content = await page.getTextContent();
    const items: PositionedText[] = content.items.flatMap((raw) => {
      if (!("str" in raw) || !raw.str.trim()) return [];
      return [{ text: raw.str.trim(), x: raw.transform[4], y: raw.transform[5] }];
    });
    const years = items.flatMap((item) => item.text.match(/20\d{2}/g) ?? []).map(Number).filter((value) => value >= 2020 && value <= 2100);
    const year = Math.max(...years);
    const starts = startDates(items, year);
    const labels = items.filter((item) => item.x >= 180 && item.x < 235 && dayNames.includes(item.text)).sort((a, b) => b.y - a.y);
    if (!starts.length || labels.length < 5) continue;
    starts.forEach((start, weekIndex) => {
      const dates = weekDates(start);
      labels.slice(weekIndex * 5, weekIndex * 5 + 5).forEach((label, dayIndex) => {
        const labelIndex = weekIndex * 5 + dayIndex;
        const top = labelIndex === 0 ? label.y + 35 : (labels[labelIndex - 1].y + label.y) / 2;
        const bottom = labelIndex === labels.length - 1 ? label.y - 55 : (label.y + labels[labelIndex + 1].y) / 2;
        const candidates = items.filter((item) => item.x >= 250 && item.x <= 430 && item.y <= top && item.y > bottom &&
          !/^(SEMAINE|JOUR|DEJEUNER|PIQUE NIQUE|GOUTERS)/i.test(item.text));
        const lines = joinLines(candidates);
        parsed.set(dates[dayIndex], lines.map((text, index) => ({
          id: createHash("sha1").update(`${dates[dayIndex]}:${text}`).digest("hex"),
          label: text,
          group: inferGroup(text, index, lines.length),
          diet: classifyDiet(text),
        })));
      });
    });
  }
  return parsed;
}

export async function fetchArgenteuil(city: City, weekStart: string, level: "elementary" | "nursery" = "elementary"): Promise<WeekMenu> {
  if (city.source.kind !== "argenteuil-pdf") throw new Error("Source municipale absente.");
  const pdfUrl = level === "nursery" ? city.source.nurseryUrl : city.source.elementaryUrl;
  const response = await fetch(pdfUrl, { next: { revalidate: 21_600 } });
  if (!response.ok) throw new Error(`Document municipal indisponible (${response.status}).`);
  const menus = await parsePdf(await response.arrayBuffer());
  return {
    city: city.slug, cityName: city.name, postalCode: city.postalCode, weekStart,
    fetchedAt: new Date().toISOString(), sourceName: "Ville d’Argenteuil", sourceUrl: city.source.municipalUrl,
    schoolLevel: level,
    days: weekDates(weekStart).map((date): MenuDay => ({ date, items: menus.get(date) ?? [] })),
  };
}
