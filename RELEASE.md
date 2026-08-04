# Release checklist

## Local release artifact

```sh
./scripts/build-release.sh
```

This produces `dist/Tack-<version>-macOS.zip` and prints its SHA-256 checksum. The default build is ad-hoc signed for local development.

## Developer ID distribution

Set `TACK_SIGNING_IDENTITY` to a valid `Developer ID Application` identity and run the release script. The build signs the app and nested widget with hardened runtime, timestamping, and the checked-in entitlements. Submit the resulting archive with `xcrun notarytool`, wait for approval, staple the ticket with `xcrun stapler`, and recreate the ZIP after stapling.

The `group.app.tack` App Group must be registered for the Apple Developer Team before distributing the widget. App Store distribution additionally requires the app sandbox and the corresponding security-scoped file-access design.

## Public release gate

- `swift test --enable-code-coverage` passes.
- `./scripts/build-release.sh` succeeds.
- `codesign --verify --deep --strict build/Tack.app` passes.
- The Developer ID signature, hardened runtime, App Group, widget gallery, document UTI, and notarization ticket are verified on a clean Mac.
- The ZIP checksum and release notes are published with the version tag.
