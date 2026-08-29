import type { Metadata } from "next";
import Link from "next/link";

import { AuthForm } from "@/components/auth-form";

export const metadata: Metadata = { title: "Créer un compte" };

export default function SignupPage() {
  return (
    <main className="auth-page">
      <section className="auth-card">
        <Link className="back-link" href="/">← Retour au studio</Link>
        <p className="eyebrow">Premier branchement</p>
        <h1>Créer votre espace.</h1>
        <p className="auth-intro">Une identité, tous vos futurs sons.</p>
        <AuthForm mode="register" />
      </section>
      <div className="auth-art signup-art" aria-hidden="true"><span>MAKE<br />NOISE.</span></div>
    </main>
  );
}
