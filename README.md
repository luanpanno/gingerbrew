# Gingerbrew

A minimal macOS menu bar app for managing [Homebrew](https://brew.sh) packages, built with native SwiftUI components.

<p align="center"><img src="Support/AppIcon.png" width="128" alt="Gingerbrew icon"></p>

<img width="367" height="545" alt="image" src="https://github.com/user-attachments/assets/f6aef819-5ba1-4243-8560-47666eef68bb" /> <img width="367" height="545" alt="image" src="https://github.com/user-attachments/assets/0a65d527-f477-4123-bee9-00dd971183cc" />


## Features

- **Installed packages at a glance.** Every formula and cask, with packages that have updates listed first.
- **Search.** Filters your installed packages and recommends ones you don't have, from the full Homebrew catalogue.
- **Package details.** Icon, description, developer, version, license, website, install date and caveats.
- **Actions.** Install, upgrade, uninstall, or **Remove Completely** (`--zap` for casks, deletes app data; all versions for formulae).
- **Dependencies.** See what a package depends on and what depends on it, and jump between them.
- **Background update checks.** Runs `brew update` every 1/6/12/24 hours (configurable), with a badge and notification when updates are available.
- **Upgrade All**, launch at login, and live `brew` output while commands run.

Requires macOS 14 Sonoma or later and Homebrew.

## Install

Download the latest `.dmg` from [Releases](https://github.com/luanpanno/gingerbrew/releases) and drag Gingerbrew to Applications.

Releases aren't notarized yet, so macOS will warn the first time. Right-click Gingerbrew → **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Gingerbrew.app
```

## Build from source

You only need the Xcode Command Line Tools (`xcode-select --install`); full Xcode also works.

```bash
scripts/build-app.sh            # builds dist/Gingerbrew.app
open dist/Gingerbrew.app
```

Other commands:

```bash
scripts/test.sh                 # run the unit tests
swift run Gingerbrew            # run without bundling (no notifications or login item)
DMG=1 UNIVERSAL=1 scripts/build-app.sh   # universal .dmg in dist/
swift scripts/make-icon.swift   # regenerate Support/AppIcon.icns
```

To open the project in Xcode, open `Package.swift`.

## How it works

| Piece | Where |
| --- | --- |
| `brew` wrapper, JSON parsing, search ranking, catalogue cache | `Sources/GingerbrewCore` |
| SwiftUI menu bar app (`MenuBarExtra`, window style) | `Sources/Gingerbrew` |
| `Info.plist`, icon, `sudo` password helper | `Support/` |
| Bundling, signing, `.dmg` | `scripts/build-app.sh` |

- Installed packages come from `brew info --json=v2 --installed`, and update availability from `brew outdated --json=v2`.
- Search for packages you don't have uses a trimmed copy of `formulae.brew.sh/api/{formula,cask}.json`, cached in `~/Library/Caches/com.luanpanno.gingerbrew` and refreshed daily.
- Some casks run installers that need `sudo`. Gingerbrew sets `SUDO_ASKPASS` to a small script that asks for your password in a native dialog. The password goes straight to `sudo` and is never stored.
- The app isn't sandboxed because it has to run `brew`, so it can't be on the Mac App Store.

## Releasing

1. Bump `CFBundleShortVersionString` in `Support/Info.plist`.
2. Tag and push: `git tag v0.1.0 && git push --tags`. The release workflow builds a universal `.dmg` and publishes it.
3. Update `version` and `sha256` in your tap's copy of [`packaging/gingerbrew.rb`](packaging/gingerbrew.rb).

Signing and notarization switch on once the repository secrets listed in `.github/workflows/release.yml` are added.

## License

[MIT](LICENSE)
