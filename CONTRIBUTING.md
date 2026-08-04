# Contributing to Tack

Tack is a local-first Mac application and an open `.tack` format. Small, focused pull requests are welcome.

## Before opening a pull request

1. Read [README.md](README.md) and [Docs/FORMAT.md](Docs/FORMAT.md).
2. Keep application changes compatible with macOS 15 and Swift 6.
3. Add or update a test for format, importer, exporter, CLI, or persistence behavior.
4. Run the full local checks:

```sh
swift test --enable-code-coverage
./scripts/build-app.sh
codesign --verify --deep --strict build/Tack.app
```

For the optional full Post-it regression fixture, set `TACK_LEGACY_FIXTURE` to a local `.postit` archive. The fixture is not committed because it is user data.

## Scope and data safety

Do not commit personal boards, captures, OCR output, credentials, or generated release artifacts. Keep test fixtures synthetic and small. Importers must never modify their source archive.

## Licensing

Application code is AGPL-3.0-only. The file format, sync protocol, and SDK-facing libraries are Apache-2.0. By contributing, you agree that your contribution is provided under the applicable license for the files you change.
