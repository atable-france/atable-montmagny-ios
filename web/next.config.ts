import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  experimental: { optimizePackageImports: ["@supabase/supabase-js"] },
  serverExternalPackages: ["pdfjs-dist"],
};

export default nextConfig;
