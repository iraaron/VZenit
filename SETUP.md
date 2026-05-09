# VZenit — macOS Setup Guide

A native macOS SwiftUI app for editing and SysEx-dumping patches on the **Casio VZ-1**, **VZ-10M**, and **VZ-8M** synthesizers.

---

## Prerequisites

- macOS 14 Sonoma or later
- Xcode 15 or later (free from the Mac App Store)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- A USB-MIDI interface connected to your VZ synth's MIDI IN/OUT

---

## Generating the Xcode Project

The repo doesn't commit the `.xcodeproj` — it's regenerated from `project.yml` via XcodeGen. This keeps the project definition merge-friendly and easy to change.

```bash
git clone git@github.com:iraaron/VZenit.git
cd VZenit
brew install xcodegen      # one time
xcodegen generate
open VZenit.xcodeproj
```

XcodeGen produces both `VZenit.xcodeproj` and `VZenit.entitlements` (with App Sandbox + USB + Audio Input enabled). To change the bundle ID, deployment target, or capabilities, edit `project.yml` and regenerate.

### Set your development team

In Xcode, select the **VZenit** target → **Signing & Capabilities** → set **Team** to your Apple ID (the free Personal Team is fine for local builds). Then **⌘R** to build and run.

The first launch will ask for permission to access MIDI devices — click **Allow**.

---

## Enable SysEx on your VZ synth

Before using the app, enable SysEx on the synthesizer itself:

- **VZ-1**: Press **EDIT** → navigate to menu **3-04** → set SysEx to **ON**
- **VZ-10M / VZ-8M**: Enter the System menu and enable **SysEx Receive/Transmit**

---

## Using VZenit

### Receiving a patch from the synth

1. Open **MIDI Settings** (toolbar cable icon) and select your interface for both Input and Output.
2. Select a preset on the VZ synth and press a key (or press the preset button).
3. The synth sends a SysEx dump automatically when you change presets (with SysEx enabled).
4. VZenit receives it and populates the editor — you'll see the patch name in the status bar.
5. Click **Get** in the toolbar to request a dump if the synth doesn't send automatically.

### Sending a patch to the synth

1. Edit parameters in the Voice Editor.
2. Click **Send** to push the current editor state to the synth's edit buffer.
3. Enable **Auto Update** to send after every parameter change (great for live tweaking).
4. On the synth, save the edit buffer to a preset memory slot in the usual way.

### Library management

- **Add patches**: Click **+** in the library sidebar.
- **Import .syx files**: File → Import SysEx… (supports multi-patch .syx files).
- **Export .syx**: Right-click a patch → Export SysEx…
- **Save library**: ⌘S saves the JSON library file. ⌘⇧S to choose a location.

---

## Project Structure

```
VZenit/
├── README.md                      ← Project overview
├── SETUP.md                       ← You are here
├── STATUS.md                      ← Feature/roadmap status
├── project.yml                    ← XcodeGen spec (regenerates .xcodeproj)
├── VZenit.entitlements            ← Generated; App Sandbox + USB + Audio Input
├── VZenit.xcodeproj               ← Generated; ignored by git
└── Sources/VZenit/
    ├── App/
    │   ├── VZenitApp.swift       ← @main entry point, menu commands
    │   └── ContentView.swift       ← Root three-panel layout
    ├── Models/
    │   ├── VZVoicePatch.swift      ← Complete 336-byte VZ voice data model
    │   ├── VZSysEx.swift           ← SysEx encode/decode (bit-accurate)
    │   └── VZLibrary.swift         ← Patch library with JSON persistence
    ├── MIDI/
    │   └── MIDIManager.swift       ← CoreMIDI wrapper, SysEx streaming
    └── Views/
        ├── VoiceEditorView.swift   ← Module routing diagram + DCO/DCA editors
        └── EnvelopeEditorView.swift ← Canvas-based drag envelope + key follow
```

---

## Key Architecture Decisions

| Decision | Rationale |
|---|---|
| **Swift/SwiftUI** | Native Mac look and feel; no dependencies |
| **CoreMIDI (legacy MIDIReadProc)** | SysEx arrives as raw bytes — easiest to accumulate F0…F7 frames |
| **336-byte model is the source of truth** | Encode/decode round-trips are lossless; verified against official Casio spec |
| **JSON library format** | Human-readable, diff-friendly, extensible |
| **.syx export** | Interoperable with other tools (vzeditor, MIDI-OX, SysEx Librarian) |

---

## What's Next (Roadmap)

- [ ] **Operation Editor** — multi-timbral (up to 8-voice) operation data editing
- [ ] **On-screen keyboard** — MIDI note preview with velocity and glissando
- [ ] **Patch randomizer / morpher** — interpolate between two patches
- [ ] **Undo/Redo** — full parameter change history
- [ ] **Bank management** — 64-patch bank dumps (VZ-1 has 64 internal presets)
- [ ] **VZ-8M support** — verify operation data format differences
- [ ] **Sysex librarian view** — bulk rename, reorder, compare patches

---

## SysEx Reference

All 336-byte offsets are documented inline in `VZSysEx.swift` and `VZVoicePatch.swift`, cross-referenced against the Casio VZ sound creation specification (see `riban-bw/vzeditor` repository, `VZ sound creation.txt`).

The SysEx frame format is:
```
F0  44  CH  00  70  [336 data bytes]  F7
     ↑   ↑   ↑   ↑
  Casio  Ch Sub  Voice
```

To request a dump from the synth:
```
F0  44  CH  00  80  F7    (0x10 | 0x70 = 0x80)
```

---

## License

This project is open source — MIT license. Portions of the SysEx specification derived from the Casio VZ-1 Service Manual and the `riban-bw/vzeditor` project (LGPL-3.0).
