# Jerusalem

A native, macOS-only church presentation app — lyrics, Bible verses, sermon points,
and video, with a slide editor, built to **never fail on Sunday morning**.

See [`docs/`](docs/) for the MVP spec, the phased implementation plan, and the UI
prototypes.

## Requirements
- macOS 14+ (Sonoma)
- A recent Xcode (26.x tested)
- [XcodeGen](https://github.com/yonyz/XcodeGen): `brew install xcodegen`

## Build & run
The Xcode project is **generated** from [`project.yml`](project.yml) (the source of
truth) and is not committed. Generate it, then open or build:

```sh
xcodegen generate
open Jerusalem.xcodeproj          # work in Xcode
# — or from the command line —
xcodebuild -scheme Jerusalem -destination 'platform=macOS' build
```

## Status
**Phase 0 — Foundation & app shell.** The Prototype C operator-window layout
(sidebar · slide grid · inspector) with empty states. Roadmap and checkpoints:
[`docs/IMPLEMENTATION-PLAN.md`](docs/IMPLEMENTATION-PLAN.md).
