export type Diet = "meat" | "vegetarian" | "fish" | "unknown";

export type MenuItem = {
  id: string;
  label: string;
  group: "starter" | "main" | "side" | "dairy" | "dessert" | "other";
  diet: Diet;
};

export type MenuDay = { date: string; items: MenuItem[] };

export type WeekMenu = {
  city: string;
  cityName: string;
  postalCode: string;
  weekStart: string;
  fetchedAt: string;
  sourceName: string;
  sourceUrl: string;
  schoolLevel?: "elementary" | "nursery";
  days: MenuDay[];
  stale?: boolean;
  documents?: { title: string; url: string }[];
  accessCode?: string;
  requiresAccount?: boolean;
};
