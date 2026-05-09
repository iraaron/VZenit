// VoiceEditorView.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS
//
// Top-level voice editor: shows the module routing diagram + per-module detail tabs.

import SwiftUI

struct VoiceEditorView: View {

    @Binding var patch: VZVoicePatch

    @State private var selectedModuleID: Int = 1   // 1–8

    var body: some View {
        HSplitView {
            // Left: routing diagram + module list
            VStack(spacing: 0) {
                RoutingDiagramView(patch: $patch, selectedModuleID: $selectedModuleID)
                    .frame(height: 260)
                    .padding(8)

                Divider()

                // Module selector list
                List(1...8, id: \.self, selection: $selectedModuleID) { n in
                    ModuleRowLabel(module: patch.modules[n - 1])
                        .tag(n)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200, maxWidth: 260)

            // Right: detail editor for selected module
            ModuleDetailView(
                module:     moduleBinding(for: selectedModuleID),
                lineMode:   lineModeBinding(for: selectedModuleID)
            )
        }
    }

    // MARK: - Bindings

    private func moduleBinding(for id: Int) -> Binding<VZModule> {
        Binding(
            get: { patch.modules[id - 1] },
            set: { patch.modules[id - 1] = $0 }
        )
    }

    private func lineModeBinding(for moduleID: Int) -> Binding<VZLine> {
        let lineIdx = (moduleID - 1) / 2
        return Binding(
            get: { patch.lines[lineIdx] },
            set: { patch.lines[lineIdx] = $0 }
        )
    }
}

// MARK: - Routing diagram

/// Draws the four-line signal-flow block diagram (M1/M2 → Line A, etc.)
struct RoutingDiagramView: View {

    @Binding var patch: VZVoicePatch
    @Binding var selectedModuleID: Int

    private let lineLetters = ["A", "B", "C", "D"]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { lineIdx in
                LineRoutingRow(
                    line:       $patch.lines[lineIdx],
                    modulator:  $patch.modules[lineIdx * 2],
                    carrier:    $patch.modules[lineIdx * 2 + 1],
                    selectedID: $selectedModuleID
                )
            }
        }
    }
}

struct LineRoutingRow: View {
    @Binding var line:      VZLine
    @Binding var modulator: VZModule   // odd module (M1, M3, M5, M7)
    @Binding var carrier:   VZModule   // even module (M2, M4, M6, M8)
    @Binding var selectedID: Int

    var body: some View {
        HStack(spacing: 4) {
            // Line label
            Text("Line \(line.id)")
                .font(.caption.bold())
                .frame(width: 46, alignment: .leading)

            // Modulator block
            ModuleBlock(module: modulator, selectedID: $selectedID)

            // Arrow + mode
            VStack(spacing: 0) {
                Image(systemName: modeIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(line.mode.description)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50)

            // Carrier block
            ModuleBlock(module: carrier, selectedID: $selectedID)

            // External phase badge
            if line.id != "A" {
                Toggle("Ext φ", isOn: $line.externalPhase)
                    .toggleStyle(.checkbox)
                    .font(.caption2)
                    .help("Phase-modulate carrier with output of previous line")
            }
        }
    }

    private var modeIcon: String {
        switch line.mode {
        case .mix:   return "plus.circle"
        case .phase: return "waveform.path.ecg"
        case .ring:  return "multiply.circle"
        }
    }
}

struct ModuleBlock: View {
    let module: VZModule
    @Binding var selectedID: Int

    private var isSelected: Bool { module.id == selectedID }

    var body: some View {
        Button {
            selectedID = module.id
        } label: {
            VStack(spacing: 1) {
                Text("M\(module.id)")
                    .font(.caption.bold())
                Text(module.dco.waveform.description)
                    .font(.system(size: 8))
            }
            .frame(width: 54, height: 36)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(module.enabled ? Color.clear : Color.red.opacity(0.7), lineWidth: 1.5)
            )
            .opacity(module.enabled ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
    }
}

struct ModuleRowLabel: View {
    let module: VZModule
    var body: some View {
        HStack {
            Image(systemName: module.enabled ? "circle.fill" : "circle")
                .foregroundStyle(module.enabled ? Color.accentColor : Color.secondary)
                .font(.caption)
            Text("M\(module.id) — \(module.dco.waveform.description)")
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text("Line \(module.lineLetter)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Module detail

struct ModuleDetailView: View {
    @Binding var module:   VZModule
    @Binding var lineMode: VZLine

    enum DetailTab: String, CaseIterable {
        case dco = "DCO"
        case envelope = "Envelope"
        case keyFollow = "Key Follow"
    }

    @State private var tab: DetailTab = .dco

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Module M\(module.id)")
                    .font(.title3.bold())
                Spacer()
                Toggle("On", isOn: $module.enabled)
                    .toggleStyle(.switch)

                // Line mode picker (only show for even modules, which are carriers)
                if module.isCarrier {
                    Picker("Mode", selection: $lineMode.mode) {
                        ForEach(VZLineMode.allCases) { mode in
                            Text(mode.description).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 130)
                    .help("Combination mode for Line \(module.lineLetter)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Picker("Detail Tab", selection: $tab) {
                ForEach(DetailTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 6)

            Divider()
                .padding(.top, 6)

            ScrollView {
                switch tab {
                case .dco:
                    DCOEditorView(dco: $module.dco)
                        .padding()
                case .envelope:
                    EnvelopeEditorView(envelope: $module.dca.envelope, label: "Amplitude Envelope")
                        .padding()
                case .keyFollow:
                    KeyFollowEditorView(curve: $module.dca.keyFollowCurve, label: "Key Follow")
                        .padding()
                }
            }
        }
    }
}

// MARK: - DCO editor

struct DCOEditorView: View {
    @Binding var dco: VZDCO

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Waveform
            LabeledContent("Waveform") {
                Picker("Waveform", selection: $dco.waveform) {
                    ForEach(VZWaveform.allCases) { w in
                        Text(w.description).tag(w)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Fixed pitch toggle
            Toggle("Fixed Pitch", isOn: $dco.fixedPitch)

            Divider()

            // Pitch controls
            Group {
                ParameterSlider(label: "Detune (semitones)",
                                value: Binding(
                                    get: { Double(dco.detuneNote) },
                                    set: { dco.detuneNote = Int($0) }
                                ),
                                range: -127...127,
                                displayFormat: { v in v >= 0 ? "+\(Int(v))" : "\(Int(v))" })

                ParameterSlider(label: "Fine (×1.6¢)",
                                value: Binding(
                                    get: { Double(dco.detuneFine) },
                                    set: { dco.detuneFine = Int($0) }
                                ),
                                range: -63...63,
                                displayFormat: { v in v >= 0 ? "+\(Int(v))" : "\(Int(v))" })

                ParameterSlider(label: "Harmonic",
                                value: Binding(
                                    get: { Double(dco.harmonic) },
                                    set: { dco.harmonic = max(1, Int($0)) }
                                ),
                                range: 1...64)
            }
        }
    }
}

// MARK: - Reusable controls

struct ParameterSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var displayFormat: ((Double) -> String)? = nil

    var body: some View {
        HStack {
            Text(label)
                .frame(minWidth: 140, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(displayFormat?(value) ?? String(format: "%.0f", value))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Global editor (vibrato, tremolo, master level)

struct GlobalEditorView: View {
    @Binding var patch: VZVoicePatch

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Master level
                GroupBox("Output") {
                    ParameterSlider(
                        label: "Master Level",
                        value: Binding(get: { Double(patch.masterLevel) },
                                       set: { patch.masterLevel = UInt8(clamping: Int($0)) }),
                        range: 0...99
                    )
                    ParameterSlider(
                        label: "Octave",
                        value: Binding(get: { Double(patch.octave) },
                                       set: { patch.octave = Int($0) }),
                        range: -2...2
                    )
                }

                // Vibrato
                GroupBox("Vibrato (DCO)") {
                    LFOEditorSection(lfo: $patch.vibrato)
                }

                // Tremolo
                GroupBox("Tremolo (DCA)") {
                    LFOEditorSection(lfo: $patch.tremolo)
                }

                // DCO pitch envelope
                GroupBox("Pitch Envelope (DCO)") {
                    EnvelopeEditorView(envelope: $patch.dcoPitchEnvelope, label: "Pitch Envelope")
                    Toggle("Range ×2", isOn: $patch.dcoPitchEnvelopeRange)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
    }
}

struct LFOEditorSection: View {
    @Binding var lfo: VZLFO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Waveform", selection: $lfo.waveform) {
                ForEach(VZLFOWaveform.allCases) { w in
                    Text(w.description).tag(w)
                }
            }
            .pickerStyle(.segmented)

            ParameterSlider(label: "Depth", value: Binding(
                get: { Double(lfo.depth) }, set: { lfo.depth = UInt8(clamping: Int($0)) }
            ), range: 0...127)

            ParameterSlider(label: "Rate", value: Binding(
                get: { Double(lfo.rate) }, set: { lfo.rate = UInt8(clamping: Int($0)) }
            ), range: 0...127)

            ParameterSlider(label: "Delay", value: Binding(
                get: { Double(lfo.delay) }, set: { lfo.delay = UInt8(clamping: Int($0)) }
            ), range: 0...127)

            Toggle("Multi (per-key trigger)", isOn: $lfo.multiMode)
        }
    }
}
