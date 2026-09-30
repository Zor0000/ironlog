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
  metadataBase: new URL("https://www.neeraj.works/setzo/"),
  applicationName: "Setzo",
  alternates: { canonical: "https://www.neeraj.works/setzo/" },
  title: "Setzo — Track your gains. Own your progress.",
  description:
    "A fast, free, no-nonsense gym tracker. Log every set, run any split, watch your PRs and streaks grow — with a lock-screen Live Activity so you never break your flow.",
  icons: { icon: "/favicon.svg" },
  openGraph: {
    title: "Setzo — Track your gains. Own your progress.",
    description:
      "A fast, free, no-nonsense gym tracker with a lock-screen Live Activity.",
    type: "website",
    siteName: "Setzo",
    url: "https://www.neeraj.works/setzo/",
    images: [{ url: "https://zor0000.github.io/setzo/website/public/app-icon.png", width: 1024, height: 1024, alt: "Setzo app icon" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Setzo — Track your gains. Own your progress.",
    images: ["https://zor0000.github.io/setzo/website/public/app-icon.png"],
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
