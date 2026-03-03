import { RootProvider } from 'fumadocs-ui/provider/next';
import './global.css';
import { Inter } from 'next/font/google';

const inter = Inter({
  subsets: ['latin'],
});

export const metadata = {
    title: {
        "default": "Fragment",
        "template": "%s | Fragment",
    },
    description: "Fragment is a simple module I made to manage Roblox's imperative UI instance system inspired by React. It currently supports state management, effects, declarative rendering, globals stores which allow you to build reactive user interfaces whilst still using default Roblox's UI components. Built specifically for Roblox's server-side environment with Rojo workflow compatibility.",
    keywords: [
        "Roblox",
        "Luau",
        "Game Development",
        "Roblox Studio",
    ],
    authors: [
        {
            name: "Cheeteau",
            url: "https://github.com/chteau"
        }
    ],
    creator: "Cheeteau",
    publisher: "Cheeteau",

    // Favicon
    icons: {
        icon: "Fragment/logo.png",
        shortcut: "/logo.png",
    },

    // Additional Metadata
    robots: {
        index: true,
        follow: true,
        googleBot: {
            index: true,
            follow: true,
            'max-video-preview': -1,
            'max-image-preview': 'large',
            'max-snippet': -1,
        },
    },

    // Open Graph / Social Media Metadata
    openGraph: {
        type: "website",
        url: "https://chteau.github.io/Fragment/",
        title: "Fragment",
        description: "Fragment is a simple module I made to manage Roblox's imperative UI instance system inspired by React. It currently supports state management, effects, declarative rendering, globals stores which allow you to build reactive user interfaces whilst still using default Roblox's UI components. Built specifically for Roblox's server-side environment with Rojo workflow compatibility.",
        siteName: "Fragment",
        images: [
            {
                url: "/banner.png",
                width: 1200,
                height: 630,
                alt: "Fragment - A simple module to manage Roblox's UI components inspired by React.",
            },
        ],
        locale: "en_US",
    },

    // Twitter Card Metadata
    twitter: {
        card: "summary_large_image",
        title: "Fragment",
        description: "Fragment is a simple module I made to manage Roblox's imperative UI instance system inspired by React. It currently supports state management, effects, declarative rendering, globals stores which allow you to build reactive user interfaces whilst still using default Roblox's UI components.",
        images: ["/banner.png"],
        creator: "@Cheeteau_",
        site: "@Cheeteau_",
    },
}

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="en" className={inter.className} suppressHydrationWarning>
      <body className="flex flex-col min-h-screen">
        <RootProvider>{children}</RootProvider>
      </body>
    </html>
  );
}
