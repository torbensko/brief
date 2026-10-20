# Publishing Brief

Brief follows the Safari Profile Studio release convention: a VERSION file, GitHub Actions, a Developer ID signature, Apple notarisation, and versioned GitHub releases containing a DMG, ZIP, and SHA256SUMS.txt. Model weights are downloaded separately by the app and never bundled in a release.

## GitHub setup

Configure these repository Actions secrets, using the same names as Safari Profile Studio:

| Secret | Value |
| --- | --- |
| CERTIFICATE_P12 | Base64-encoded Developer ID Application certificate, including its private key |
| CERTIFICATE_PASSWORD | Password protecting that P12 export |
| APPLE_ID | Apple account used for notarisation |
| APPLE_ID_PASSWORD | App-specific password for notarisation |
| APPLE_TEAM_ID | Apple developer team ID |

The import step determines SIGNING_IDENTITY from the supplied certificate. Local Apple Development signing is for development only; distribution requires Developer ID Application. Secrets stay in GitHub, not in source files.

After setting the secrets, run **Build and release** manually from Actions. Set the optional repository variable `RELEASE_ENABLED=true` to also release automatically when VERSION changes on main. It is deliberately off until signing is configured. Increment VERSION and update RELEASE_NOTES.md for later releases. Published versions are never overwritten.

The default runner is `xcode-27`, the GitHub image with Xcode 27 and Swift 6.4 required by the verified MLX/Metal packaging path. `MACOS_RUNNER` can select another Apple Silicon runner with that toolchain. Both workflows install the Metal Toolchain component. The release is arm64 only, with a macOS 14 deployment target; Intel is unsupported.

The workflow signs the worker and app with hardened runtime, grants the app the audio-input entitlement required for microphone capture, notarises and staples the app, creates a DMG with an Applications shortcut, notarises/staples the DMG, and publishes only after all steps succeed. An unsigned preview is available as a CI artifact and is clearly named as such.

## Local checks

```sh
Scripts/check.sh
Scripts/package.sh --unsigned
```

Packaging uses a release build. Distribution can also run locally with the signing identity and Apple credentials supplied through environment variables; avoid shell history containing secrets.

## Identity and artwork

The displayed app and downloadable bundle are Brief. Internal Swift targets and the existing `local.LocalDictation` bundle identifier remain stable. Data remains in `~/Library/Application Support/LocalDictation`, preserving downloaded models and settings from the original app. The first Developer ID build can require regranting permissions because it has a different signing identity from the development build.

`Resources/Brief.png` is the full-bleed square master: no border, mask, or pre-rounded corners. `Scripts/build-icon.sh` derives the app icon sizes without applying a mask. The website uses this same master. Let the operating system and website styles handle presentation.

## Identifying an installed build

The menu and Settings show the version and build number from the running app's bundle. `VERSION` is the release version; bump it for each published update (patch for fixes, minor for compatible features, major for breaking changes). Local builds use the Git commit count as their build number unless `BUILD_NUMBER` is supplied. Build after committing so the number identifies that revision. “View latest release” opens GitHub for comparison; it does not silently install an update.
