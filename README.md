# VZenit

A native macOS voice editor and SysEx librarian for the **Casio VZ-1**, **VZ-10M**, and **VZ-8M** synthesizers.

Built in Swift / SwiftUI. No dependencies. Bit-accurate handling of the full 336-byte VZ voice format, verified against Casio's official spec.

> **Status:** Source code complete for the core editor; Xcode project setup is manual (see [SETUP.md](SETUP.md)). See [STATUS.md](STATUS.md) for a full feature breakdown.

---

## What it does

- **Live MIDI editing** — receive a patch from the synth, edit it visually, send it back. Auto-update mode pushes changes after every parameter tweak.
- **Visual signal flow** — see the iPD module routing (M1–M8 across Lines A–D) at a glance, with click-to-edit module blocks.
- **Drag-to-edit envelopes** — Canvas-based 8-step envelopes with movable sustain and end markers, plus 6-point key-follow breakpoint editing.
- **Patch library** — JSON-backed library with full CRUD, multi-patch `.syx` import/export, and per-patch metadata.
- **All three VZ models** — VZ-1, VZ-10M, and VZ-8M (operation editor for multi-timbral mode is planned).

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ (to build)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- A USB-MIDI interface connected to your VZ synth

## Getting started

```bash
git clone git@github.com:iraaron/VZenit.git
cd VZenit
brew install xcodegen      # one time
xcodegen generate
open VZenit.xcodeproj
```

In Xcode, set your Team under **Signing & Capabilities**, then **⌘R**. Full walkthrough in [SETUP.md](SETUP.md).

## Project layout

```
VZenit/
├── README.md                 ← you are here
├── SETUP.md                  ← detailed setup walkthrough
├── STATUS.md                 ← feature/roadmap status
├── project.yml               ← XcodeGen spec — single source of truth
└── Sources/VZenit/
    ├── App/                  ← @main entry point + root view
    ├── Models/               ← 336-byte voice model, SysEx codec, library
    ├── MIDI/                 ← CoreMIDI wrapper, SysEx streaming
    └── Views/                ← Voice editor, envelope editor
```

## Roadmap

Highlights from [STATUS.md](STATUS.md):

- Operation editor (multi-timbral mode)
- On-screen MIDI keyboard preview
- Undo/redo
- 64-patch bank dump/restore
- Patch compare / morph
- Unit tests

## Acknowledgements

The 336-byte voice format was cross-referenced against the [`riban-bw/vzeditor`](https://github.com/riban-bw/vzeditor) project's `VZ sound creation.txt` documentation.

## License

MIT. Portions of the SysEx specification derived from the Casio VZ-1 Service Manual and `riban-bw/vzeditor` (LGPL-3.0).
