import type { Metadata } from "next";
import Link from "next/link";

import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Robine Amp", template: "%s · Robine Amp" },
  description: "Façonnez votre son dans un studio d'amplis et de pédales vivant.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="fr">
      <body>
        <header className="site-header">
          <Link href="/" className="brand" aria-label="Robine Amp, accueil">
            <span className="brand-mark" aria-hidden="true">R</span>
            <span>Robine Amp</span>
          </Link>
          <nav aria-label="Navigation principale">
            <Link href="/login">Connexion</Link>
            <Link className="nav-cta" href="/signup">Essayer Robine</Link>
          </nav>
        </header>
        {children}
        <footer>
          <span>© {new Date().getFullYear()} Robine Amp</span>
          <span>Conçu pour les sons qui ne rentrent pas dans une case.</span>
        </footer>
      </body>
    </html>
  );
}
