# Robine Amp web

Next.js application for the public landing page and user accounts.

## Local setup

```sh
cp .env.example .env.local
docker compose up -d
npm install
npm run db:migrate
npm run dev
```

Open <http://localhost:3000>. The account API exposes:

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/logout`
- `GET /api/auth/me`

Registration and login create an opaque 30-day session. Only the SHA-256 digest of the session token is stored in PostgreSQL; the browser receives the token in a `HttpOnly`, `SameSite=Lax` cookie. Passwords are derived with Node's `scrypt` implementation and a random per-user salt.

## Commands

```sh
npm run lint
npm test
npm run build
npm run db:generate # after changing src/db/schema.ts
npm run db:migrate
```

Set `DATABASE_URL` in every environment. In production, terminate TLS before Next.js so the session cookie is sent with its `Secure` flag.
