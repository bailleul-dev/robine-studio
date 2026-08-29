"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

type AuthFormProps = { mode: "login" | "register" };

export function AuthForm({ mode }: AuthFormProps) {
  const router = useRouter();
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const isRegister = mode === "register";

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setLoading(true);
    const data = new FormData(event.currentTarget);
    const body = {
      email: data.get("email"),
      password: data.get("password"),
      ...(isRegister ? { displayName: data.get("displayName") } : {}),
    };

    try {
      const response = await fetch(`/api/auth/${mode}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      });
      const result = (await response.json()) as { error?: string };
      if (!response.ok) {
        setError(result.error ?? "Impossible de continuer.");
        return;
      }
      router.push("/account");
      router.refresh();
    } catch {
      setError("Le serveur est indisponible. Réessayez dans un instant.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="auth-form" onSubmit={submit}>
      {isRegister && (
        <label>
          Nom
          <input name="displayName" autoComplete="name" minLength={2} maxLength={80} required />
        </label>
      )}
      <label>
        Adresse e-mail
        <input name="email" type="email" autoComplete="email" maxLength={320} required />
      </label>
      <label>
        Mot de passe
        <input
          name="password"
          type="password"
          autoComplete={isRegister ? "new-password" : "current-password"}
          minLength={isRegister ? 12 : 1}
          maxLength={128}
          required
        />
        {isRegister && <span className="field-hint">12 caractères minimum</span>}
      </label>
      {error && <p className="form-error" role="alert">{error}</p>}
      <button className="button primary full" type="submit" disabled={loading}>
        {loading ? "Un instant…" : isRegister ? "Créer mon compte" : "Se connecter"}
      </button>
      <p className="auth-switch">
        {isRegister ? "Déjà inscrit ?" : "Nouveau chez Robine ?"}{" "}
        <Link href={isRegister ? "/login" : "/signup"}>
          {isRegister ? "Se connecter" : "Créer un compte"}
        </Link>
      </p>
    </form>
  );
}
