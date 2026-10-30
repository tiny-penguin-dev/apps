# apps

Small standalone apps.

## Layout

```
apps/<name>/     one folder per app, self-contained (builds and ships on its own)
packages/<name>/ shared code, only once 2+ apps actually use it
```

## Adding an app

1. Create `apps/<name>/` with its own `README.md` and `CLAUDE.md`.
2. Keep it self-contained: no imports from other apps, only from `packages/`.
