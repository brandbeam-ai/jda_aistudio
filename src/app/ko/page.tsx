import type { Metadata } from "next";

import { MicrositePage } from "@/components/microsite-page";
import { loadMicrosite } from "@/lib/microsite";

const microsite = loadMicrosite("fcmo-microsite-v3-ko.html");

export const metadata: Metadata = {
  title: microsite.title,
  description: microsite.description,
  alternates: {
    canonical: "/ko",
    languages: {
      en: "/",
      ko: "/ko",
    },
  },
};

export default function KoreanHomePage() {
  return <MicrositePage data={microsite} />;
}
