import type { Metadata } from "next";
import Link from "next/link";

import { AuthForm } from "@/components/auth-form";

export const metadata: Metadata = { title: "Connexion" };

export default function LoginPage() {
  return (
    <main className="auth-page">
      <section className="auth-card">
        <Link className="back-link" href="/">← Retour au studio</Link>
        <p className="eyebrow">Content de vous revoir</p>
        <h1>Reprendre la session.</h1>
        <p className="auth-intro">Vos rigs et vos réglages vous attendent.</p>
        <AuthForm mode="login" />
      </section>
      <div className="auth-art" aria-hidden="true"><span>PLAY<br />LOUD.</span></div>
    </main>
  );
}
