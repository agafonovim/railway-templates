# Plausible Analytics — Railway template

Self-host [Plausible Analytics](https://plausible.io) Community Edition on Railway: privacy-friendly, cookie-free web analytics. Modernized from the (outdated) [railwayapp-templates/plausible](https://github.com/railwayapp-templates/plausible).

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/plausible-analytics-ce?referralCode=iv6Pc4&utm_medium=integration&utm_source=template&utm_campaign=generic)

**Stack:** Plausible CE `v3.2.1` + ClickHouse `26.3-alpine` (tuned) + Railway-managed PostgreSQL.

```
                 ┌─────────────────────────────┐
  Internet ─TLS─▶│ plausible  (public :8000)   │   official image, no volume
                 └──────────┬──────────┬────────┘
            private (railway.internal) │
              ┌───────────────┘        └───────────────┐
        ┌─────▼──────┐                          ┌───────▼────────┐
        │ Postgres   │ accounts, sites          │ clickhouse     │ events
        │ (managed)  │ :5432  (private)          │ :8123 (private)│  + volume
        └────────────┘                          └────────────────┘
```
Only the Plausible app is public. Both databases are reachable **only** over Railway's private network.

## What's in this repo
The only buildable part — the **tuned ClickHouse image** (official base + Plausible v3.2.1 config, adapted for Railway):

```
plausible/clickhouse/
  Dockerfile                         FROM clickhouse/clickhouse-server:26.3-alpine + COPY config
  config.d/
    logs.xml                         query_log kept (30-day TTL), other system logs dropped
    low-resources.xml                mark_cache_size 500 MB (low-RAM plans)
    railway-listen.xml               <listen_host>::</listen_host>  (Railway dual-stack)
  users.d/
    low-resources-profile.xml        default profile: max_threads=1, no parallel parse/format
  railway.json                       builder DOCKERFILE + restart ON_FAILURE
```

Postgres (managed) and Plausible (official image) need no files — they're configured as template metadata (below).

## Services & variables

### Postgres — Railway managed PostgreSQL
Add via Railway's one-click Postgres. No public domain. Exposes `PGUSER`, `POSTGRES_PASSWORD`, `RAILWAY_PRIVATE_DOMAIN` for references.

### clickhouse — built from this repo
- **Source:** this GitHub repo · **Root Directory:** `/plausible/clickhouse` · Builder: Dockerfile (from `railway.json`).
  > The Railway "Config File" path does **not** follow Root Directory — set it to the absolute `/plausible/clickhouse/railway.json`.
- **Volume:** `/var/lib/clickhouse` · **No public domain.**

| Variable | Value |
|---|---|
| `CLICKHOUSE_DB` | `plausible_events_db` |
| `CLICKHOUSE_USER` | `plausible` |
| `CLICKHOUSE_PASSWORD` | `${{secret(32)}}` |
| `CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT` | `1` |

### plausible — official image
- **Source:** Docker image `ghcr.io/plausible/community-edition:v3.2.1` · **Public domain** (Railway-generated) · **No volume.**
- **Custom Start Command** (the stock image's default does not migrate):
  ```
  /bin/sh -c "/entrypoint.sh db createdb && /entrypoint.sh db migrate && /entrypoint.sh run"
  ```

| Variable | Value | Notes |
|---|---|---|
| `BASE_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | tracks the live domain |
| `SECRET_KEY_BASE` | `${{secret(64)}}` | ≥64 bytes, sessions |
| `DATABASE_URL` | `postgres://${{Postgres.PGUSER}}:${{Postgres.POSTGRES_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/plausible_db` | dedicated DB, auto-created |
| `CLICKHOUSE_DATABASE_URL` | `http://plausible:${{clickhouse.CLICKHOUSE_PASSWORD}}@${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}:8123/plausible_events_db` | private host |
| `DISABLE_REGISTRATION` | `invite_only` | first signup allowed, then locked |
| `ENABLE_EMAIL_VERIFICATION` | `false` | no SMTP by default |
| `HTTP_PORT` | `8000` | Plausible listen port |
| `PORT` | `8000` | Railway routing target (see gotchas) |
| `LISTEN_IP` | `0.0.0.0` | bind for the public edge |
| `TMPDIR` | `/tmp` | no app volume (see gotchas) |

Secrets use Railway's [template variable functions](https://docs.railway.com/variables/reference) (`${{secret()}}`) — regenerated per deploy. Cross-service references use the **private** domain.

`TOTP_VAULT_KEY` is intentionally omitted — Plausible derives it from `SECRET_KEY_BASE`. If you enable 2FA and later rotate `SECRET_KEY_BASE`, set `TOTP_VAULT_KEY` explicitly first (`openssl rand -base64 32`) so existing 2FA secrets keep decrypting.

## Railway gotchas baked in
- **`PORT=8000`** — Railway routes the public domain via `PORT`; Plausible only reads `HTTP_PORT`. Without `PORT` set, the edge returns `502` with `x-railway-fallback: true`.
- **No app volume on Plausible** — a Railway volume mounts root-owned and shadows the image's `/var/lib/plausible`, crashing tzdata on boot. Durable data lives in ClickHouse (events) and Postgres (accounts), both persisted.
- **`listen_host ::`** — ClickHouse must bind IPv6 for Railway's private DNS; the official image does this via `docker_related_config.xml`, and `railway-listen.xml` makes it explicit.

## Publish as a template
1. Push this repo to a **public** GitHub repo (Railway needs it to build the ClickHouse service).
2. In Railway, create a project and add the three services exactly as specified above (managed Postgres; `clickhouse` from this repo with Root Directory `/plausible/clickhouse`; `plausible` from the image + start command). Set all variables, the ClickHouse volume, and a public domain on `plausible`.
3. Verify it deploys (see below).
4. Dashboard → **Create Template** from the project → write per-service descriptions, mark required/optional variables → publish → share the template URL.

## After deploying (lockdown)
1. Open the public URL → register the **first admin** (allowed by `invite_only`).
2. Set `DISABLE_REGISTRATION=true` → redeploy (closes signups).
3. Enable **TOTP 2FA** on the admin account.
4. Add your site (bare domain, e.g. `example.com`) and install the tracking snippet.

## Optional
- **Email** (invites / verification): set `MAILER_ADAPTER`, `MAILER_EMAIL`, and `SMTP_*` (or `MAILGUN_*` / `POSTMARK_API_KEY` / `SENDGRID_API_KEY`).
- **Custom domain:** add it to the `plausible` service; `BASE_URL` follows `${{RAILWAY_PUBLIC_DOMAIN}}`, or pin `BASE_URL` to the custom domain.
- **Backups:** ClickHouse data lives in the `/var/lib/clickhouse` volume; consider [`altinity/clickhouse-backup`](https://github.com/Altinity/clickhouse-backup) → S3. Managed Postgres has Railway backups.

## Verify
- `clickhouse` deploy `SUCCESS`; private ping: `wget -qO- http://clickhouse.railway.internal:8123/ping` → `Ok.`
- `plausible` logs: `db createdb` → `db migrate` succeed → `run`; no Postgres/ClickHouse errors; no tzdata crash.
- `curl -sI https://<public-domain>/` → `302 → /register` (not `502`).

## Upgrades
Bump the Plausible image tag (`v3.2.1` → newer) and keep the ClickHouse config in sync with that Plausible version's `clickhouse/` directory. ClickHouse profile settings track the Plausible release.

---
Plausible CE is AGPLv3. You pay only for Railway infrastructure (~$5–15/mo; ClickHouse is the heaviest component — give it ≥2 GB RAM).
