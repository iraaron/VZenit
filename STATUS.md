# VZenit — Project Status

**Last updated:** 2026-05-09  
**Latest release:** [v0.0.1](https://github.com/iraaron/VZenit/releases/tag/v0.0.1) — first preview (prerelease, hardware-untested)  
**Target platform:** macOS 14+ (native Swift/SwiftUI)  
**Synths supported:** Casio VZ-1, VZ-10M, VZ-8M

---

## ✅ Completed

### Data Model (`Models/VZVoicePatch.swift`)
- Complete Swift model for the full 336-byte VZ voice patch
- All parameters covered: 8 modules (M1–M8), 4 lines (A–D), DCO waveform/detune/fixed pitch, 8-step DCA envelopes, 8-step DCO pitch envelope, key follow curves (6-point breakpoint), key velocity sensitivity, vibrato, tremolo, master level, octave
- Enums for all discrete parameters: `VZWaveform` (8 types), `VZLineMode` (Mix/Phase/Ring), `VZLFOWaveform`, `VZSynthModel`
- Convenience accessors (`module(1...8)`, `line("A"..."D")`)
- Full `Codable` conformance for JSON persistence

### SysEx Codec (`Models/VZSysEx.swift`)
- Bit-accurate encode and decode of the full 336-byte voice format
- SysEx frame construction: `F0 44 CH 00 70 [336 bytes] F7`
- Dump request builder: `F0 44 CH 00 80 F7`
- All byte offsets and bit masks documented inline, cross-referenced against Casio's official spec (`VZ sound creation.txt`)
- Error handling via `VZSysExError` with descriptive messages
- SysEx stream scanner (`extractMessages`) for parsing multi-patch .syx files
- Round-trip encode → decode is lossless

### MIDI Manager (`MIDI/MIDIManager.swift`)
- CoreMIDI client and port setup using `MIDIReadProc` (legacy API — best for raw SysEx byte access)
- Dynamic port discovery with refresh on plug/unplug events
- Input port connect/disconnect per endpoint
- SysEx frame accumulation (F0…F7 streaming across multiple packets)
- Sends decoded `VZVoicePatch` to SwiftUI via `@Published var receivedPatch`
- `sendVoice(_:channel:)` and `requestVoiceDump(channel:)` convenience methods
- `@MainActor` singleton — safe to observe from SwiftUI views

### Library Manager (`Models/VZLibrary.swift`)
- Observable patch collection with full CRUD (add, update, remove, reorder)
- JSON persistence with metadata (name, created, modified, notes)
- File open/save/save-as via `URL`
- Import from raw `.syx` files (single or multi-patch)
- Export single patch or full library to `.syx`
- Group-based filtering

### App Scaffold (`App/VZenitApp.swift`, `App/ContentView.swift`)
- `@main` SwiftUI app entry point
- macOS menu commands: File (New Library, Import SysEx, Export SysEx), MIDI (Request Dump, Send Patch, Refresh Ports)
- Three-panel `NavigationSplitView`: library sidebar → voice editor → (future inspector)
- Patch library sidebar with context menu (Duplicate, Export, Delete)
- MIDI control bar per patch (name field, Get, Send, Auto Update toggle)
- Auto-update mode: sends to synth after every parameter change
- SysEx file import/export via `fileImporter` / `fileExporter`
- Error alerts wired throughout
- `SyxDocument` FileDocument wrapper for export sheet

### Voice Editor (`Views/VoiceEditorView.swift`)
- Signal-flow routing diagram showing M1–M8 arranged in Lines A–D
- Clickable module blocks (highlight selected, dim disabled, show waveform name)
- Line combination mode picker (Mix / Phase Mod / Ring Mod) per line
- External phase toggle for Lines B, C, D
- Module detail panel with three tabs: DCO, Envelope, Key Follow
- DCO editor: waveform picker, detune (semitones), fine (×1.6¢), harmonic, fixed pitch toggle
- Vibrato and Tremolo global editors (waveform, depth, rate, delay, multi mode)
- Master level and octave controls
- Global DCO pitch envelope editor

### Envelope Editor (`Views/EnvelopeEditorView.swift`)
- Canvas-based visual envelope with drag-to-edit level nodes
- Green filled curve with grid lines on dark background
- Sustain point marker (blue vertical bar + "S" label)
- End step marker (red vertical bar + "E" label)
- Compact numeric grids for Rate and Level per step (0–127)
- Checkbox rows for Sustain and End step assignment
- Envelope depth slider
- Key follow curve editor: 6-point breakpoint table with MIDI note + note name display

### MIDI Settings Sheet
- Picker for input and output MIDI ports
- Refresh button for hot-plug scenarios

### Setup Guide (`SETUP.md`)
- XcodeGen-based project setup (`brew install xcodegen && xcodegen generate`)
- Entitlements auto-generated from `project.yml` (App Sandbox + USB + Audio Input)
- VZ synth SysEx enable instructions (per model)
- Usage workflow (receive, edit, send, save)
- SysEx frame reference
- Architecture rationale table

### Build (`project.yml`, MIT `LICENSE`)
- XcodeGen spec defines the macOS 14+ app target, bundle ID `io.github.iraaron.VZenit`, App Sandbox + USB + Audio Input + user-selected files entitlements
- Builds cleanly via `xcodebuild` — no source-code warnings
- MIT license, public repo at https://github.com/iraaron/VZenit

### Tests (`Tests/VZenitTests/`)
- `VZenitTests` XCTest bundle target wired up via `project.yml`
- **28 tests** across two suites: codec correctness (22) + randomizer (6)
- Codec coverage: dump-request frames, encode framing, encode-decode-encode byte idempotence, full-struct round-trip equality on the default patch, custom name + waveform + line-mode + octave + master-level round-trips, multi-message stream extraction, all four decode error paths
- Randomizer coverage: determinism with seeded RNG, distinctness across seeds, **property test that any random patch round-trips losslessly** (catches range violations the randomizer might introduce), envelope structure invariants, master-level audibility
- Caught (and fixed) the dump-request command-byte bug during test authoring

### Patch randomizer (`VZVoicePatch+Random.swift`)
- `VZVoicePatch.random(using:)` — constrained random patch generation, generic over `RandomNumberGenerator` so tests can use a seeded LCG
- Covers timbre-shaping fields: per-module waveform/detune/harmonic/fixed-pitch, DCA envelope (rates + levels + one sustain step), line combination modes (biased toward Mix), vibrato/tremolo depth, master level (audible range), octave
- Wired into the library sidebar via a 🎲 die.face.5 button next to `+`

### Model defaults reconciled with wire format
- `VZEnvelope.depth` default 99 → 0 (the field is a 6-bit value 0–63 on the wire, only meaningful for the DCO pitch envelope; DCA envelopes don't encode it at all)
- `VZEnvelope.steps[7].isEnd` default false → true (decoder marks the step at `endStep` with `isEnd=true`; default constructor now matches that canonical post-decode form)
- `VZVoicePatch.dcoKeyFollowCurve` overridden to `.flat(value: 0)` (the DCO key follow's value field is 6-bit; the previous shared default of 99 clamped to 35 on encode)
- `VZVoicePatch.name` default trailing spaces dropped (decoder trims, so the trailing whitespace was lost on the first round-trip)
- New `VZKeyFollowCurve.flat(value:)` factory for explicit flat curves

---

## 🔲 Not Yet Started

| Feature | Notes |
|---|---|
| **Operation Editor** | Multi-timbral operation data (format similar to voice, separate SysEx command 0x60) |
| **On-screen MIDI keyboard** | Monophonic MIDI note preview; velocity by click position; glissando on drag |
| **Undo / Redo** | SwiftUI `UndoManager` integration on `VZVoicePatch` mutations |
| **64-patch bank management** | VZ-1 has 64 internal preset slots; bulk dump/restore |
| **Patch compare / morph** | Side-by-side diff or parameter interpolation between two patches |
| **Accessibility** | VoiceOver labels, keyboard navigation for all controls |
| **App icon** | Design and asset catalog |
| **VZ-8M verification** | Confirm operation data format differences vs VZ-1/10M |

---

## File Map

```
VZenit/
├── README.md                              ← project overview
├── STATUS.md                              ← this file
├── SETUP.md                               ← detailed setup walkthrough
├── LICENSE                                ← MIT
├── project.yml                            ← XcodeGen spec
├── Sources/VZenit/
│   ├── App/
│   │   ├── VZenitApp.swift                ✅ @main, menus, notifications
│   │   └── ContentView.swift              ✅ root 3-panel layout
│   ├── Models/
│   │   ├── VZVoicePatch.swift             ✅ 336-byte voice data model
│   │   ├── VZVoicePatch+Random.swift      ✅ constrained patch randomizer
│   │   ├── VZSysEx.swift                  ✅ bit-accurate encode/decode
│   │   └── VZLibrary.swift                ✅ JSON library + .syx import/export
│   ├── MIDI/
│   │   └── MIDIManager.swift              ✅ CoreMIDI wrapper + SysEx streaming
│   └── Views/
│       ├── VoiceEditorView.swift          ✅ routing diagram + DCO/DCA editors
│       └── EnvelopeEditorView.swift       ✅ canvas envelope + key follow
└── Tests/VZenitTests/
    ├── VZSysExTests.swift                 ✅ 22 codec tests
    └── VZVoicePatchRandomTests.swift      ✅ 6 randomizer tests
```

---

## Next Session Suggested Starting Points

1. **Operation Editor** — the operation SysEx format is structurally similar to voice; `VZ operation creation.txt` in the reference repo has the spec
2. **Patch compare / morph** — extends the randomizer pattern: pure operations on `VZVoicePatch`, no synth needed
3. **On-screen keyboard** — straightforward SwiftUI Canvas + CoreMIDI note-on/off
4. **App icon** — design + asset catalog
