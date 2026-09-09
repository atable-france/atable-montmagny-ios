import { readFile } from "node:fs/promises";
import { getDocument } from "pdfjs-dist/legacy/build/pdf.mjs";

const data = new Uint8Array(await readFile(process.argv[2]));
const pdf = await getDocument({ data, useWorkerFetch: false, isEvalSupported: false }).promise;
const page = await pdf.getPage(Number(process.argv[3] ?? 1));
const content = await page.getTextContent();
for (const item of content.items) {
  if (!("str" in item) || !item.str.trim()) continue;
  console.log(`${item.transform[4].toFixed(1)}\t${item.transform[5].toFixed(1)}\t${item.str}`);
}
