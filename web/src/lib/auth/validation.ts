import { z } from "zod";

const email = z
  .string()
  .trim()
  .toLowerCase()
  .max(320, "Adresse e-mail trop longue.")
  .email("Adresse e-mail invalide.");

const password = z
  .string()
  .min(12, "Le mot de passe doit contenir au moins 12 caractères.")
  .max(128, "Le mot de passe est trop long.");

export const registerSchema = z.object({
  email,
  password,
  displayName: z
    .string()
    .trim()
    .min(2, "Le nom doit contenir au moins 2 caractères.")
    .max(80, "Le nom est trop long."),
});

export const loginSchema = z.object({ email, password: z.string().min(1).max(128) });

export function firstValidationError(error: z.ZodError): string {
  return error.issues[0]?.message ?? "Données invalides.";
}
