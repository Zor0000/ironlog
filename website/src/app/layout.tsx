import type { Metadata, Viewport } from "next";
import { Bebas_Neue, DM_Sans } from "next/font/google";
import "./globals.css";

const bebas = Bebas_Neue({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-bebas",
  display: "swap",
});

const dmSans = DM_Sans({
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700"],
  variable: "--font-dm",
  display: "swap",
});

export const metadata: Metadata = {
  title: "IronLog — Track your gains. Own your progress.",
  description:
    "A fast, free, no-nonsense gym tracker. Log every set, run any split, watch your PRs and streaks grow — with a lock-screen Live Activity so you never break your flow.",
  icons: { icon: "/favicon.svg" },
  openGraph: {
    title: "IronLog — Track your gains. Own your progress.",
    description:
      "A fast, free, no-nonsense gym tracker with a lock-screen Live Activity.",
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#0a0a0a",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="en"
      className={`${bebas.variable} ${dmSans.variable} h-full antialiased`}
    >
      <body className="min-h-full bg-ink text-fg">{children}</body>
    </html>
  );
}
