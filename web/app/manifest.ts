import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "À table",
    short_name: "À table",
    description: "Les menus scolaires de votre ville.",
    start_url: "/",
    display: "standalone",
    background_color: "#fffaf0",
    theme_color: "#245c48",
    icons: [],
  };
}
