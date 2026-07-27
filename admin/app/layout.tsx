import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const protocol =
    requestHeaders.get("x-forwarded-proto") ??
    (host?.startsWith("localhost") ? "http" : "https");
  const metadataBase = host ? new URL(`${protocol}://${host}`) : undefined;

  return {
    metadataBase,
    title: {
      default: "TV-WALL Control",
      template: "%s · TV-WALL Control",
    },
    description: "電視牆節點、播放內容與設備狀態管理後台。",
    openGraph: {
      title: "TV-WALL Control",
      description: "即時掌握所有電視牆節點、播放內容與運作狀態。",
      type: "website",
      images: [
        {
          url: "/og.png",
          width: 1730,
          height: 909,
          alt: "TV-WALL Control 電視牆營運中心",
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: "TV-WALL Control",
      description: "即時掌握所有電視牆節點、播放內容與運作狀態。",
      images: ["/og.png"],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-Hant">
      <body>{children}</body>
    </html>
  );
}
