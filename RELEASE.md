# Release checklist

## Local release artifact

```sh
./scripts/build-release.sh
```

This produces `dist/Tack-<version>-macOS.zip` and prints its SHA-256 checksum. It needs `TACK_SIGNING_IDENTITY` set to a real Apple Development or Developer ID identity; ad-hoc signing is rejected because the widget's App Group requires a team signature. An Apple Development build runs only on Macs you build it on. Sharing a download with other people requires a Developer ID identity (paid Apple Developer Program) and notarization.

## Developer ID distribution

Set `TACK_SIGNING_IDENTITY` to a valid `Developer ID Application` identity and run the release script. The build signs the app and nested widget with hardened runtime, timestamping, and the checked-in entitlements. Submit the resulting archive with `xcrun notarytool`, wait for approval, staple the ticket with `xcrun stapler`, and recreate the ZIP after stapling.

The macOS app and widget share the team-scoped App Group `<TeamID>.app.tack`. The build script reads the Team ID from the signing certificate (or `TACK_TEAM_ID`), resolves `$(TeamIdentifierPrefix)` in the checked-in entitlements, and writes the group into both Info.plists as `TackAppGroupIdentifier`. Official builds use Team `YAU948K7T5`. The `TackWidgets` extension must carry the App Sandbox entitlement or macOS will reject it. App Store distribution additionally requires the app sandbox and the corresponding security-scoped file-access design.

## Public release gate

- `swift test --enable-code-coverage` passes.
- `./scripts/build-release.sh` succeeds.
- `codesign --verify --deep --strict build/Tack.app` passes.
- The Developer ID signature, hardened runtime, App Group, widget gallery, document UTI, and notarization ticket are verified on a clean Mac.
- The ZIP checksum and release notes are published with the version tag.
