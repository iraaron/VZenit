// EnvelopeEditorView.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS
//
// A Canvas-based drag-and-drop envelope editor supporting 8 steps,
// a moveable sustain point, and an end-step marker.

import SwiftUI

struct EnvelopeEditorView: View {

    @Binding var envelope: VZEnvelope
    var label: String = "Envelope"

    // Layout
    private let canvasHeight: CGFloat = 160
    private let nodeRadius:   CGFloat = 6
    private let stepCount               = 8

    // Drag state
    @State private var dragIndex: Int? = nil
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.bold())

            // Canvas
            GeometryReader { geo in
                ZStack {
                    canvasBackground(size: geo.size)
                    envelopePath(size: geo.size)
                    envelopeNodes(size: geo.size)
                    sustainMarker(size: geo.size)
                    endMarker(size: geo.size)
                }
                .gesture(dragGesture(size: geo.size))
            }
            .frame(height: canvasHeight)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            // Depth + numeric step editors
            ParameterSlider(
                label: "Depth",
                value: Binding(
                    get: { Double(envelope.depth) },
                    set: { envelope.depth = UInt8(clamping: Int($0)) }
                ),
                range: 0...127
            )

            // Step grid (compact numeric editors)
            stepGrid
        }
    }

    // MARK: - Canvas drawing

    private func canvasBackground(size: CGSize) -> some View {
        Canvas { ctx, sz in
            // Grid lines every 32 levels
            for y in stride(from: 0.0, through: sz.height, by: sz.height / 4) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: sz.width, y: y))
                ctx.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            }
        }
    }

    private func envelopePath(size: CGSize) -> some View {
        Canvas { ctx, sz in
            var path = Path()
            let pts  = nodePositions(size: sz)

            guard !pts.isEmpty else { return }
            path.move(to: pts[0])
            for pt in pts.dropFirst() { path.addLine(to: pt) }

            ctx.stroke(path, with: .color(Color.green.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5))

            // Fill area under envelope
            var fill = path
            fill.addLine(to: CGPoint(x: pts.last!.x, y: sz.height))
            fill.addLine(to: CGPoint(x: pts.first!.x, y: sz.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(Color.green.opacity(0.12)))
        }
    }

    private func envelopeNodes(size: CGSize) -> some View {
        let positions = nodePositions(size: size)
        return ForEach(0..<stepCount, id: \.self) { i in
            let pos = positions[i]
            Circle()
                .fill(dragIndex == i ? Color.yellow : Color.green)
                .frame(width: nodeRadius * 2, height: nodeRadius * 2)
                .position(pos)
        }
    }

    private func sustainMarker(size: CGSize) -> some View {
        Group {
            if let si = envelope.sustainStep {
                let x = stepX(index: si, width: size.width)
                let barRect = CGRect(x: x - 1, y: 0, width: 2, height: size.height)
                Canvas { ctx, _ in
                    ctx.fill(Path(barRect), with: .color(Color.blue.opacity(0.7)))
                    // "S" label
                    ctx.draw(Text("S").font(.caption2).foregroundStyle(.blue),
                             at: CGPoint(x: x, y: 8))
                }
            }
        }
    }

    private func endMarker(size: CGSize) -> some View {
        let ei = Int(envelope.endStep)
        let x  = stepX(index: ei, width: size.width)
        let barRect = CGRect(x: x - 1, y: 0, width: 2, height: size.height)
        return Canvas { ctx, _ in
            ctx.fill(Path(barRect), with: .color(Color.red.opacity(0.5)))
            ctx.draw(Text("E").font(.caption2).foregroundStyle(.red),
                     at: CGPoint(x: x, y: size.height - 8))
        }
    }

    // MARK: - Geometry helpers

    /// X position for a given step index.
    private func stepX(index: Int, width: CGFloat) -> CGFloat {
        let margin: CGFloat = 20
        let usable = width - margin * 2
        return margin + CGFloat(index) * usable / CGFloat(stepCount - 1)
    }

    /// Y position for a given level (0–127, inverted so 127 = top).
    private func levelY(level: UInt8, height: CGFloat) -> CGFloat {
        let margin: CGFloat = 10
        let usable = height - margin * 2
        return margin + usable * (1.0 - Double(level) / 127.0)
    }

    private func nodePositions(size: CGSize) -> [CGPoint] {
        (0..<stepCount).map { i in
            CGPoint(
                x: stepX(index: i, width: size.width),
                y: levelY(level: envelope.steps[i].level, height: size.height)
            )
        }
    }

    // MARK: - Drag gesture

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragIndex == nil {
                    // Find nearest node to start position
                    let positions = nodePositions(size: size)
                    let hit = positions.enumerated().min { a, b in
                        distance(a.element, value.startLocation) < distance(b.element, value.startLocation)
                    }
                    if let hit, distance(hit.element, value.startLocation) < nodeRadius * 2.5 {
                        dragIndex = hit.offset
                    }
                }
                guard let idx = dragIndex else { return }

                // Convert Y position to level
                let margin: CGFloat = 10
                let usable = size.height - margin * 2
                let rawY   = value.location.y
                let clamped = max(margin, min(size.height - margin, rawY))
                let fraction = 1.0 - (clamped - margin) / usable
                let newLevel = UInt8(clamping: Int(fraction * 127).clamped(to: 0...127))
                envelope.steps[idx].level = newLevel
            }
            .onEnded { _ in
                dragIndex = nil
            }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    // MARK: - Step grid (text fields)

    private var stepGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Rate row
            HStack(spacing: 2) {
                Text("Rate").frame(width: 44, alignment: .trailing).font(.caption)
                ForEach(0..<stepCount, id: \.self) { i in
                    CompactNumberField(value: Binding(
                        get: { Int(envelope.steps[i].rate) },
                        set: { envelope.steps[i].rate = UInt8(clamping: $0) }
                    ), range: 0...127)
                }
            }

            // Level row
            HStack(spacing: 2) {
                Text("Level").frame(width: 44, alignment: .trailing).font(.caption)
                ForEach(0..<stepCount, id: \.self) { i in
                    CompactNumberField(value: Binding(
                        get: { Int(envelope.steps[i].level) },
                        set: { envelope.steps[i].level = UInt8(clamping: $0) }
                    ), range: 0...127)
                }
            }

            // Sustain + End toggles row
            HStack(spacing: 2) {
                Text("Sus").frame(width: 44, alignment: .trailing).font(.caption)
                ForEach(0..<stepCount, id: \.self) { i in
                    Toggle("", isOn: Binding(
                        get: { envelope.steps[i].isSustain },
                        set: { if $0 { envelope.setSustain(at: i) } }
                    ))
                    .toggleStyle(.checkbox)
                    .frame(width: 28)
                }
            }

            HStack(spacing: 2) {
                Text("End").frame(width: 44, alignment: .trailing).font(.caption)
                ForEach(0..<stepCount, id: \.self) { i in
                    Toggle("", isOn: Binding(
                        get: { Int(envelope.endStep) == i },
                        set: { if $0 { envelope.setEnd(at: i) } }
                    ))
                    .toggleStyle(.checkbox)
                    .frame(width: 28)
                }
            }
        }
    }
}

// MARK: - Compact numeric text field

struct CompactNumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .multilineTextAlignment(.center)
            .font(.system(size: 10, design: .monospaced))
            .frame(width: 28, height: 20)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { text = "\(value)" }
            .onChange(of: value) { text = "\(value)" }
            .onChange(of: focused) { if !focused { commit() } }
            .onSubmit { commit() }
    }

    private func commit() {
        if let v = Int(text) {
            value = v.clamped(to: range)
        }
        text = "\(value)"
    }
}

// MARK: - Key follow editor

struct KeyFollowEditorView: View {
    @Binding var curve: VZKeyFollowCurve
    var label: String

    private let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.subheadline.bold())

            // Simple grid for the 6 breakpoints
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Point").font(.caption.bold())
                    Text("Key (MIDI)").font(.caption.bold())
                    Text("Note").font(.caption.bold())
                    Text("Level").font(.caption.bold())
                }
                ForEach(0..<6, id: \.self) { i in
                    GridRow {
                        Text("\(i + 1)").font(.caption)

                        CompactNumberField(value: Binding(
                            get: { Int(curve.points[i].key) },
                            set: { curve.points[i].key = UInt8(clamping: $0) }
                        ), range: 0...127)

                        Text(noteName(for: Int(curve.points[i].key)))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 36)

                        HStack {
                            Slider(value: Binding(
                                get: { Double(curve.points[i].value) },
                                set: { curve.points[i].value = UInt8(clamping: Int($0)) }
                            ), in: 0...127, step: 1)
                            Text("\(curve.points[i].value)")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 28)
                        }
                    }
                }
            }
        }
    }

    private func noteName(for midi: Int) -> String {
        let octave = (midi / 12) - 1
        let name   = noteNames[midi % 12]
        return "\(name)\(octave)"
    }
}

// MARK: - MIDI settings sheet

struct MIDISettingsSheet: View {

    @EnvironmentObject var midi: MIDIManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MIDI Settings")
                .font(.title2.bold())

            GroupBox("Input Port") {
                Picker("Input", selection: Binding(
                    get: { midi.selectedInput },
                    set: { if let ep = $0 { midi.connect(input: ep) } }
                )) {
                    Text("None").tag(Optional<MIDIEndpoint>.none)
                    ForEach(midi.inputs) { ep in
                        Text(ep.name).tag(Optional(ep))
                    }
                }
                .pickerStyle(.menu)
            }

            GroupBox("Output Port") {
                Picker("Output", selection: Binding(
                    get: { midi.selectedOutput },
                    set: { if let ep = $0 { midi.connect(output: ep) } }
                )) {
                    Text("None").tag(Optional<MIDIEndpoint>.none)
                    ForEach(midi.outputs) { ep in
                        Text(ep.name).tag(Optional(ep))
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Button("Refresh Ports") { midi.refreshEndpoints() }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
    }
}

// MARK: - Helpers

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
