# VZenit — macOS Setup Guide

A native macOS SwiftUI app for editing and SysEx-dumping patches on the **Casio VZ-1**, **VZ-10M**, and **VZ-8M** synthesizers.

---

## Prerequisites

- macOS 13 Ventura or later
- Xcode 15 or later (free from the Mac App Store)
- A USB-MIDI interface connected to your VZ synth's MIDI IN/OUT

---

## Xcode Project Setup

The source files are already written. You just need to create an Xcode project and add them.

### Step 1 — Create a new macOS App project

1. Open Xcode → **File → New → Project**
2. Choose **macOS → App**
3. Configure:
   - **Product Name**: `VZenit`
   - **Bundle Identifier**: `com.yourname.VZenit` (change to whatever you like)
   - **Interface**: SwiftUI
   - **Language**: Swift
4. Save the project **inside** the `VZenit/` folder (next to `Sources/`).

### Step 2 — Add the source files

1. In the Xcode Project Navigator, right-click the `VZenit` group → **Add Files to "VZenit"…**
2. Navigate to `Sources/VZenit/` and select all sub-folders:
   - `App/`
   - `Models/`
   - `MIDI/`
   - `Views/`
3. Make sure **"Add to target: VZenit"** is checked, then click **Add**.
4. Delete the template `ContentView.swift` and `VZenitApp.swift` that Xcode generated (the ones in `Sources/VZenit/App/` replace them).

### Step 3 — Configure entitlements

VZenit needs permission to access MIDI hardware. In the Project Navigator:

1. Select your project → target **VZenit** → tab **Signing & Capabilities**
2. Click **+ Capability** and add **App Sandbox**
3. Under **Hardware**, enable:
   - ✅ **USB**  ← required for USB-MIDI interfaces
   - ✅ **Audio Input** ← some MIDI drivers need this

Alternatively, for development you can temporarily **disable** App Sandbox entirely (the app will still run).

Your `.entitlements` file should contain at minimum:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.device.usb</key>
<true/>
```

### Step 4 — Enable SysEx on your VZ synth

Before using the app, enable SysEx on the synthesizer itself:

- **VZ-1**: Press **EDIT** → navigate to menu **3-04** → set SysEx to **ON**
- **VZ-10M / VZ-8M**: Enter the System menu and enable **SysEx Receive/Transmit**

---

## Building & Running

Press **⌘R** in Xcode to build and run.

The first launch may ask for permission to access MIDI devices — click **Allow**.

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
├── SETUP.md                        ← You are here
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
