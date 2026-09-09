import type { Diet } from "./types";

const meat = ["boeuf", "bœuf", "veau", "porc", "poulet", "dinde", "volaille", "agneau", "mouton", "canard", "jambon", "lardon", "saucisse", "chorizo", "merguez", "bacon", "lapin", "cordon bleu"];
const fish = ["poisson", "colin", "hoki", "merlu", "lieu", "cabillaud", "saumon", "thon", "sardine", "truite", "morue", "anchois", "crevette", "moule", "surimi"];

function normalized(value: string) {
  return ` ${value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9œ]+/g, " ")} `;
}

export function classifyDiet(label: string): Diet {
  const value = normalized(label);
  const includes = (word: string) => value.includes(` ${normalized(word).trim()} `);
  const hasMeat = meat.some(includes);
  const hasFish = fish.some(includes);
  if ((includes("vegetarien") || includes("vegetarienne") || includes("vegetal") || includes("lentilles facon bolognaise")) && !hasMeat && !hasFish) return "vegetarian";
  if (hasMeat) return "meat";
  if (hasFish) return "fish";
  if (includes("omelette") || includes("croque fromage") || includes("pois chiche")) return "vegetarian";
  return "unknown";
}
