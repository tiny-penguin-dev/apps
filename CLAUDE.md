# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this repo is

A monorepo of small apps. Each app lives in `apps/<name>/` and is independent: it builds, tests and ships on its own. Shared code goes in `packages/<name>/`.

Most apps don't need a backend. Some talk to `lanata-server` (separate repo: `lanata/lanata-server`). Server changes for those apps happen in that repo, not here.

## Rules

- **One app per folder.** Never import code from another app. If two apps need the same code, move it to `packages/`.
- **Don't create a package for one app.** Only extract shared code once a second app actually needs it.
- **Each app has its own `CLAUDE.md`** with how to build, run and test it. Read it before working on that app, and keep it up to date when you change how the app works.
- **Scope changes to one app** unless the task is about shared code or repo setup.
- **Never commit secrets.** Use `.env` files (gitignored) and commit a `.env.example`.

## Apps that use lanata-server

- Talk to the server through the shared `LanataNetworking` client (currently in `lanata-server/apps/ios/LanataNetworking`; planned to move into `packages/` here).
- The server's API contract is its OpenAPI spec (`/api/openapi.json` on the running server, `api-spec/openapi.json` in that repo).
- Auth goes through Cloudflare Access + a Lanata user token. See `docs/multi-app-runbook.md` in `lanata-server`.

## Apple setup

- Team `YNMFSUHQ46`, bundle IDs under `me.lanata.*`.
- Each app gets its own bundle ID, keychain group and app group.
