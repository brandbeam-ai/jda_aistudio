import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "JD Alchemy",
  description: "JD Alchemy microsite",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
