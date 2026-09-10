export type CitySource =
  | { kind: "foodi"; posId: string; municipalUrl: string }
  | { kind: "argenteuil-pdf"; elementaryUrl: string; nurseryUrl: string; municipalUrl: string };

export type City = {
  slug: string;
  name: string;
  postalCode: string;
  aliases?: string[];
  source: CitySource;
};

export const cities: City[] = [
  {
    slug: "montmagny",
    name: "Montmagny",
    postalCode: "95360",
    source: {
      kind: "foodi",
      posId: "UG9zOjM4ODg1ODg=",
      municipalUrl: "https://www.villedemontmagny.fr/enfance/le-periscolaire/la-restauration-scolaire/",
    },
  },
  {
    slug: "argenteuil",
    name: "Argenteuil",
    postalCode: "95100",
    source: {
      kind: "argenteuil-pdf",
      elementaryUrl: "https://www.argenteuil.fr/sites/default/files/media/downloads/elementaires.pdf",
      nurseryUrl: "https://www.argenteuil.fr/sites/default/files/media/downloads/maternelles.pdf",
      municipalUrl: "https://www.argenteuil.fr/fr/restauration-scolaire",
    },
  },
];

export function cityBySlug(slug: string) {
  return cities.find((city) => city.slug === slug);
}

export function normalizeCityName(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("fr-FR")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function cityByLocation(name: string, postalCode: string) {
  const normalized = normalizeCityName(name);
  return cities.find((city) =>
    city.postalCode === postalCode &&
    [city.name, ...(city.aliases ?? [])].some((candidate) => normalizeCityName(candidate) === normalized),
  );
}
