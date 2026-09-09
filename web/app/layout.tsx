import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "À table — les menus de la cantine",
  description: "Les menus scolaires de votre ville, clairs et faciles à lire.",
  manifest: "/manifest.webmanifest",
};

export const viewport: Viewport = { themeColor: "#fffaf0", width: "device-width", initialScale: 1 };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="fr"><body>{children}</body></html>;
}
