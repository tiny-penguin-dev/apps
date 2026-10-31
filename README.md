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

Apps go Product → Design → Build, and Gabriel approves each stage. See
[docs/app-workflow.md](docs/app-workflow.md) for the steps and
[docs/brand.md](docs/brand.md) for the shared Tiny Penguin look and feel.

1. Create `apps/<name>/` with `PRODUCT.md` from `docs/templates/`, plus a short `README.md`.
2. Once the product is approved, add `DESIGN.md` and clickable mockups in `design/`.
3. Once the design is approved, add `BUILD.md`, then the code and a `CLAUDE.md`.
4. Keep it self-contained: no imports from other apps, only from `packages/`.
5. For an iOS app, follow "Adding a new iOS app" in `docs/ios-release.md`.
