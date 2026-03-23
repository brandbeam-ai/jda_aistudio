import { readFileSync } from "node:fs";
import path from "node:path";

export type MicrositeData = {
  lang: string;
  title: string;
  description: string;
  links: string[];
  styles: string[];
  bodyHtml: string;
  scriptContents: string[];
};

function extractFirst(input: string, pattern: RegExp): string {
  const match = input.match(pattern);
  return match?.[1]?.trim() ?? "";
}

export function loadMicrosite(fileName: string): MicrositeData {
  const filePathByName: Record<string, string> = {
    "fcmo-microsite-v3.html": path.join(
      process.cwd(),
      "fcmo-microsite-v3.html",
    ),
    "fcmo-microsite-v3-ko.html": path.join(
      process.cwd(),
      "fcmo-microsite-v3-ko.html",
    ),
  };
  const filePath = filePathByName[fileName];
  if (!filePath) {
    throw new Error(`Unsupported microsite file: ${fileName}`);
  }
  const html = readFileSync(filePath, "utf8");

  const lang = extractFirst(html, /<html[^>]*\slang="([^"]+)"/i) || "en";
  const title = extractFirst(html, /<title>([\s\S]*?)<\/title>/i);
  const description = extractFirst(
    html,
    /<meta[^>]*name="description"[^>]*content="([^"]*)"/i,
  );

  const links = Array.from(html.matchAll(/<link\b[^>]*>/gi)).map(
    (m) => m[0],
  );
  const styles = Array.from(html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi))
    .map((m) => m[1])
    .filter(Boolean);

  const bodyMatch = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
  const fullBody = bodyMatch?.[1] ?? "";

  const scriptPattern = /<script[^>]*>([\s\S]*?)<\/script>/gi;
  const scriptContents = Array.from(fullBody.matchAll(scriptPattern))
    .map((m) => m[1]?.trim() ?? "")
    .filter(Boolean);

  const bodyHtml = fullBody.replace(scriptPattern, "").trim();

  return {
    lang,
    title,
    description,
    links,
    styles,
    bodyHtml,
    scriptContents,
  };
}
