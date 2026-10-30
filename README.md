# apps

Small standalone apps. Most are fully independent; a few talk to [`lanata-server`](https://github.com/lanata/lanata-server).

## Layout

```
apps/<name>/     one folder per app, self-contained (builds and ships on its own)
packages/<name>/ shared code, only once 2+ apps actually use it
```

## Adding an app

1. Create `apps/<name>/` with its own `README.md` and `CLAUDE.md`.
2. Keep it self-contained: no imports from other apps, only from `packages/`.
3. If it talks to `lanata-server`, follow `docs/multi-app-runbook.md` in that repo.
