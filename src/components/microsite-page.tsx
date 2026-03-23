import Script from "next/script";

import type { MicrositeData } from "@/lib/microsite";

type MicrositePageProps = {
  data: MicrositeData;
};

export function MicrositePage({ data }: MicrositePageProps) {
  return (
    <>
      {data.styles.map((style, index) => (
        <style key={`style-${index}`} dangerouslySetInnerHTML={{ __html: style }} />
      ))}

      <div
        lang={data.lang}
        suppressHydrationWarning
        dangerouslySetInnerHTML={{ __html: data.bodyHtml }}
      />

      {data.scriptContents.map((scriptContent, index) => (
        <Script
          key={`script-${index}`}
          id={`microsite-script-${data.lang}-${index}`}
          strategy="lazyOnload"
          dangerouslySetInnerHTML={{ __html: scriptContent }}
        />
      ))}
    </>
  );
}
