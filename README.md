# apps

Small standalone apps.

## Layout

```
apps/<name>/      one folder per app, self-contained (builds and ships on its own)
packages/<name>/  shared code, only once 2+ apps actually use it
config/ios/       shared Xcode build settings for every iOS app
docs/             repo-wide guides (e.g. ios-release.md)
.github/workflows CI: one reusable iOS workflow + one small workflow per app
```

## Apps

| App | What it is |
|---|---|
| [StackWrite](apps/stackwrite) | iOS keyboard: write a whole word as one stacked stroke |

## Adding an app

1. Create `apps/<name>/` with its own `README.md` and `CLAUDE.md`.
2. Keep it self-contained: no imports from other apps, only from `packages/`.
3. For an iOS app, follow "Adding a new iOS app" in `docs/ios-release.md`.
