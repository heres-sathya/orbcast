# Building from source

## Requirements

- macOS 15 or later
- Xcode Command Line Tools: `xcode-select --install` (Swift 6 toolchain; full Xcode is not required)

## Build

```sh
git clone https://github.com/heres-sathya/orbcast.git
cd orbcast
./scripts/build.sh
open build/Orbcast.app
```

`build.sh` creates the icon set, compiles `Sources/*.swift` for `arm64` and `x86_64`, merges them into a universal binary with `lipo`, copies `Resources/Info.plist`, and ad-hoc signs the bundle.


## Package a DMG

```sh
./scripts/make_dmg.sh     # → dist/Orbcast.dmg
```

## Project layout

```
orbcast/
├── Sources/          Swift source (see architecture.md)
├── Resources/        Info.plist and the 1024×1024 app icon
├── scripts/          build.sh, make_dmg.sh, deploy_website.sh
├── website/          Static site for orbcast.pages.dev
├── assets/           Images used in this documentation
└── docs/             Documentation
```

## Release checklist

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Add an entry to [`CHANGELOG.md`](../CHANGELOG.md).
3. `./scripts/build.sh && ./scripts/make_dmg.sh`
4. Test the DMG on a clean Mac: install, grant permissions, record, export.
5. Create a GitHub release, tag `vX.Y.Z`, and attach `dist/Orbcast.dmg`.
6. `./scripts/deploy_website.sh` to publish the website with the new DMG.

## Website

The site in `website/` is plain HTML and CSS, hosted on Cloudflare Pages. `scripts/deploy_website.sh` copies it with the latest DMG and deploys it with `wrangler`. The first time, run `npx wrangler login`.

## Notarization (optional)

With an Apple Developer ID, sign with your identity instead of `-`, then notarize and staple:

```sh
codesign --force --options runtime --sign "Developer ID Application: <Name> (<TEAMID>)" build/Orbcast.app
xcrun notarytool submit dist/Orbcast.dmg --keychain-profile <profile> --wait
xcrun stapler staple dist/Orbcast.dmg
```
