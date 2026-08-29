import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { LogoutButton } from "@/components/logout-button";
import { getUserForToken, SESSION_COOKIE } from "@/lib/auth/session";

export const metadata: Metadata = { title: "Mon compte" };
export const dynamic = "force-dynamic";

export default async function AccountPage() {
  const cookieStore = await cookies();
  const user = await getUserForToken(cookieStore.get(SESSION_COOKIE)?.value);
  if (!user) redirect("/login");

  return (
    <main className="account-page">
      <section className="account-card">
        <p className="eyebrow">Compte actif</p>
        <h1>Bonjour, {user.displayName}.</h1>
        <p className="auth-intro">Votre espace Robine est prêt à accueillir ses premiers rigs.</p>
        <dl>
          <div><dt>Nom</dt><dd>{user.displayName}</dd></div>
          <div><dt>Adresse e-mail</dt><dd>{user.email}</dd></div>
          <div><dt>Membre depuis</dt><dd>{new Intl.DateTimeFormat("fr-FR", { dateStyle: "long" }).format(user.createdAt)}</dd></div>
        </dl>
        <LogoutButton />
      </section>
    </main>
  );
}
