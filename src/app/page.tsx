import type { Metadata } from "next";

import { MicrositePage } from "@/components/microsite-page";
import { loadMicrosite } from "@/lib/microsite";

const microsite = loadMicrosite("fcmo-microsite-v4.html");

export const metadata: Metadata = {
  title: microsite.title,
  description: microsite.description,
  alternates: {
    canonical: "/",
    languages: {
      en: "/",
      ko: "/ko",
    },
  },
};

export default function HomePage() {
  return <MicrositePage data={microsite} />;
}
