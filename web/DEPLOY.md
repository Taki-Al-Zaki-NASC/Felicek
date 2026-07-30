# Deploying the web app

**This cannot be done for you from a coding session** — both hosts need
credentials tied to your account. What follows is the whole job, and it is
short.

The app is in `web/`, not the repository root. That one setting is what most
first deploys get wrong: the build runs at the root, finds no `package.json`,
and fails with something unhelpful.

---

## Vercel (recommended)

Next.js with server rendering is what Vercel is built for, and the free tier
covers this comfortably.

1. [vercel.com/new](https://vercel.com/new) → **Import Git Repository** →
   `Taki-Al-Zaki-NASC/Felicek`.
2. **Root Directory: `web`.** Set this in the import screen. It cannot be set
   from `vercel.json` — it is a project setting.
3. Branch: `claude/felicek-web-app` (or merge to `main` first and use that).
4. **Environment Variables** — copy all six from `web/.env.example`, filling
   `NEXT_PUBLIC_FIREBASE_API_KEY` and `NEXT_PUBLIC_FIREBASE_APP_ID` from
   Firebase → Project settings → your Web app. Set them for Production,
   Preview and Development.
5. Deploy.

Every push to that branch redeploys, and pull requests get their own preview
URL.

### One thing to do in Firebase afterwards

Add the Vercel domain to **Firebase → Authentication → Settings → Authorised
domains**. Until you do, sign-in fails with `auth/unauthorised-domain` — the
app is fine, the project simply does not trust that origin yet.

---

## Cloudflare Pages

Works, with one extra step: Next.js server rendering needs the Workers
runtime rather than the Node one.

1. `npm i -D @cloudflare/next-on-pages` in `web/`.
2. Cloudflare dashboard → **Workers & Pages** → Create → Pages → Connect to
   Git.
3. Root directory `web`, build command `npx @cloudflare/next-on-pages@1`,
   output directory `.vercel/output/static`.
4. Add the same six environment variables.
5. Compatibility flags: `nodejs_compat`, for both Production and Preview.

Same Firebase authorised-domain step as above.

---

## Why not GitHub Pages

Pages serves static files only. Exporting this app statically would mean
giving up server rendering — which is the entire reason it is Next.js rather
than Flutter Web, since public job listings have to be indexable. The tagged
release channel still uses Pages for `website/` (the APK download page,
privacy and terms); that part is genuinely static.

---

## About `web/.env.local`

It is committed, which is unusual but not a leak: Firebase web keys identify a
project and authorise nothing, and they ship in every client anyway.
`firestore.rules` is the real boundary.

It is listed in `.gitignore`, so tracking it is inconsistent. If you deploy
from git and set environment variables in the host, the file is redundant and
worth untracking:

```bash
git rm --cached web/.env.local
```

Do that *after* the host has the variables, not before, or the next build has
no configuration at all.
