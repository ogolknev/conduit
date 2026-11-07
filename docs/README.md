# Developer documentation

[English README](../README.md) · [Русский README](../README.ru.md)

- [Agent guidance and continuous improvement](../AGENTS.md)
- [Architecture and decisions](ARCHITECTURE.md)
- [Development workflow](DEVELOPMENT.md)
- [Build and run checks](BUILDING.md)
- [Prepare a release](RELEASING.md)
- [Interface and icons](DESIGN.md)
- [Validation and known test limits](VALIDATION.md)
- [Earlier validation notes, Russian](history/validation-0.2-0.3.ru.md)
- [Third-party components and licenses](../THIRD_PARTY_NOTICES.md)

## Repository layout

| Path | Contents |
| --- | --- |
| `Sources/Conduit/` | macOS app, interface and platform integrations |
| `Sources/ConduitCore/` | Protocol, transport helpers and validation |
| `Tests/ConduitCoreTests/` | Swift tests |
| `android/src/` | Android companion and Shizuku integration |
| `android/res/` | Native Android resources and generated translations |
| `android/tests/` | JVM checks |
| `localization/` | Shared English/Russian catalog and native macOS strings |
| `design/` | Brand geometry, SVG and compiled macOS icon catalog |
| `scripts/` | Builds, resource generation and checks |
| `docs/` | Developer documentation and current screenshots |
| `licenses/` | Unmodified third-party license texts |
| `.agents/skills/` | Narrow project workflows loaded on demand |
| `.github/workflows/` | macOS icon catalog build workflow |

`work/`, `dist/` and other build output are ignored. Keep toolchains, signing keys and device diagnostics outside tracked files. Generated resources required by the builds remain checked in and are verified by their generators.

Conduit code and artwork are released under [MIT](../LICENSE). See [third-party notices](../THIRD_PARTY_NOTICES.md) for bundled dependencies.
