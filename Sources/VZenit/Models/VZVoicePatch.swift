// VZVoicePatch.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS
//
// Models the complete 336-byte SysEx voice patch data for the Casio VZ series.
// All parameter offsets and bit layouts derived from the official Casio SysEx spec.

import Foundation

// MARK: - Enumerations

/// DCO waveform selection (3 bits, values 0–7)
enum VZWaveform: UInt8, CaseIterable, Identifiable, Codable, CustomStringConvertible {
    case sine   = 0
    case saw1   = 1
    case saw2   = 2
    case saw3   = 3
    case saw4   = 4
    case saw5   = 5
    case noise1 = 6
    case noise2 = 7

    var id: UInt8 { rawValue }

    var description: String {
        switch self {
        case .sine:   return "Sine"
        case .saw1:   return "Saw 1"
        case .saw2:   return "Saw 2"
        case .saw3:   return "Saw 3"
        case .saw4:   return "Saw 4"
        case .saw5:   return "Saw 5"
        case .noise1: return "Noise 1"
        case .noise2: return "Noise 2"
        }
    }
}

/// Line combination mode for a module pair (2 bits)
/// Each line (A–D) pairs two modules: Line A = M1+M2, B = M3+M4, C = M5+M6, D = M7+M8
enum VZLineMode: UInt8, CaseIterable, Identifiable, Codable, CustomStringConvertible {
    case mix   = 0   // Simple sum: My + Mx
    case phase = 1   // Phase modulation: My(Mx) — Mx modulates phase of My
    case ring  = 2   // Ring modulation: (My × Mx) + My

    var id: UInt8 { rawValue }

    var description: String {
        switch self {
        case .mix:   return "Mix"
        case .phase: return "Phase Mod"
        case .ring:  return "Ring Mod"
        }
    }
}

/// LFO waveform for vibrato and tremolo (2 bits)
enum VZLFOWaveform: UInt8, CaseIterable, Identifiable, Codable, CustomStringConvertible {
    case triangle = 0
    case sawUp    = 1
    case sawDown  = 2
    case square   = 3

    var id: UInt8 { rawValue }

    var description: String {
        switch self {
        case .triangle: return "Triangle"
        case .sawUp:    return "Saw Up"
        case .sawDown:  return "Saw Down"
        case .square:   return "Square"
        }
    }
}

/// Supported Casio VZ synthesizer models
enum VZSynthModel: String, CaseIterable, Codable, Identifiable {
    case vz1  = "VZ-1"
    case vz10m = "VZ-10M"
    case vz8m = "VZ-8M"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// SysEx sub-ID byte (all VZ models share the same format; channel is set separately)
    var sysExSubID: UInt8 { 0x00 }
}

// MARK: - Envelope

/// A single step in an 8-step VZ envelope
struct VZEnvelopeStep: Codable, Equatable {
    /// Time/rate for this step (0–127). Higher = slower in the VZ.
    var rate: UInt8 = 0
    /// Target level for this step (0–127)
    var level: UInt8 = 99
    /// Whether this step is the sustain hold point
    var isSustain: Bool = false
    /// Whether this step is the end point (remaining steps are skipped)
    var isEnd: Bool = false
}

/// An 8-step envelope (used for both DCA per-module and global DCO pitch)
struct VZEnvelope: Codable, Equatable {
    var steps: [VZEnvelopeStep] = Array(repeating: VZEnvelopeStep(), count: 8)
    /// Overall envelope depth (0–127)
    var depth: UInt8 = 99
    /// Index of the end step (0–7)
    var endStep: UInt8 = 7

    /// Returns the index of the sustain step, if any
    var sustainStep: Int? { steps.firstIndex(where: \.isSustain) }

    mutating func setSustain(at index: Int) {
        for i in steps.indices { steps[i].isSustain = false }
        if steps.indices.contains(index) { steps[index].isSustain = true }
    }

    mutating func setEnd(at index: Int) {
        endStep = UInt8(clamping: index)
        for i in steps.indices { steps[i].isEnd = (i == index) }
    }
}

// MARK: - Key Follow

/// A single point in a 6-point key follow curve
struct VZKeyFollowPoint: Codable, Equatable {
    /// MIDI note (0–127)
    var key: UInt8 = 0
    /// Level or rate at this key position (0–127)
    var value: UInt8 = 99
}

/// 6-point breakpoint curve used for key follow (DCA level and DCO pitch)
struct VZKeyFollowCurve: Codable, Equatable {
    var points: [VZKeyFollowPoint] = [
        VZKeyFollowPoint(key: 0,   value: 99),
        VZKeyFollowPoint(key: 24,  value: 99),
        VZKeyFollowPoint(key: 48,  value: 99),
        VZKeyFollowPoint(key: 72,  value: 99),
        VZKeyFollowPoint(key: 96,  value: 99),
        VZKeyFollowPoint(key: 120, value: 99),
    ]
}

// MARK: - Module Components

/// DCO (Digital Controlled Oscillator) settings for one VZ module
struct VZDCO: Codable, Equatable {
    var waveform: VZWaveform = .sine
    /// Coarse detune in semitones, signed (-127 to +127)
    var detuneNote: Int = 0
    /// Fine detune in ~1.6-cent steps (-63 to +63)
    var detuneFine: Int = 0
    /// When true, pitch is fixed (not track keyboard)
    var fixedPitch: Bool = false
    /// Harmonic number (1–64); adjusting this sets detuneNote automatically
    var harmonic: Int = 1
}

/// DCA (Digital Controlled Amplifier) settings for one VZ module
struct VZDCA: Codable, Equatable {
    var envelope: VZEnvelope = VZEnvelope()
    var keyFollowCurve: VZKeyFollowCurve = VZKeyFollowCurve()
    /// Key velocity curve shape (0–7)
    var keyVelocityCurve: UInt8 = 0
    /// Key velocity sensitivity (0–31)
    var keyVelocitySensitivity: UInt8 = 0
    /// Amplitude sensitivity to modulation sources (0–7)
    var ampSensitivity: UInt8 = 0
}

/// One of the 8 VZ synthesis modules (M1–M8), each with a DCO and DCA
struct VZModule: Codable, Equatable, Identifiable {
    /// 1-based module number (1–8)
    var id: Int
    /// Whether this module is active
    var enabled: Bool = true
    var dco: VZDCO = VZDCO()
    var dca: VZDCA = VZDCA()

    /// The line this module belongs to (A=M1/M2, B=M3/M4, C=M5/M6, D=M7/M8)
    var lineLetter: String {
        switch id {
        case 1, 2: return "A"
        case 3, 4: return "B"
        case 5, 6: return "C"
        case 7, 8: return "D"
        default:   return "?"
        }
    }

    /// Whether this is the "odd" (carrier) module in its pair (M2, M4, M6, M8)
    var isCarrier: Bool { id % 2 == 0 }
}

// MARK: - Line Configuration

/// Configuration for one of the four internal lines (A–D)
struct VZLine: Codable, Equatable, Identifiable {
    /// "A", "B", "C", or "D"
    var id: String
    /// How the two modules in this line are combined
    var mode: VZLineMode = .mix
    /// When true, the even module (carrier) can be phase-modulated by the previous line's output.
    /// Only valid for Lines B, C, D (M4, M6, M8).
    var externalPhase: Bool = false

    /// The two module IDs in this line (odd modulator, even carrier)
    var moduleIDs: (Int, Int) {
        switch id {
        case "A": return (1, 2)
        case "B": return (3, 4)
        case "C": return (5, 6)
        case "D": return (7, 8)
        default:  return (1, 2)
        }
    }
}

// MARK: - LFO

/// Vibrato (DCO pitch) or Tremolo (DCA amp) global LFO settings
struct VZLFO: Codable, Equatable {
    var waveform: VZLFOWaveform = .triangle
    /// Depth of modulation (0–127)
    var depth: UInt8 = 0
    /// Speed of LFO (0–127)
    var rate: UInt8 = 0
    /// Delay before LFO onset (0–127)
    var delay: UInt8 = 0
    /// Multi mode: each key independently triggers the LFO
    var multiMode: Bool = false
}

// MARK: - Complete Voice Patch

/// A complete Casio VZ voice patch — the full 336-byte voice parameter set.
///
/// This is the top-level model for the VZ editor. Instances can be serialized to/from
/// the VZ SysEx wire format via `VZSysEx.encode(_:)` / `VZSysEx.decode(_:)`.
struct VZVoicePatch: Codable, Equatable, Identifiable {
    var id: UUID = UUID()

    // MARK: Voice identity
    /// Up to 12 ASCII characters (truncated/padded on encode)
    var name: String = "INIT VOICE  "
    var description: String = ""
    var group: String = ""
    var synth: VZSynthModel = .vz10m

    // MARK: Lines (A–D) — module pair configurations
    var lines: [VZLine] = [
        VZLine(id: "A"),
        VZLine(id: "B"),
        VZLine(id: "C"),
        VZLine(id: "D"),
    ]

    // MARK: Modules (M1–M8)
    var modules: [VZModule] = (1...8).map { VZModule(id: $0) }

    // MARK: Global DCO (pitch) envelope
    var dcoPitchEnvelope: VZEnvelope = VZEnvelope()
    /// Range multiplier for the DCO pitch envelope
    var dcoPitchEnvelopeRange: Bool = false
    var dcoKeyFollowCurve: VZKeyFollowCurve = VZKeyFollowCurve()
    var dcoKeyVelocityCurve: UInt8 = 0
    var dcoKeyVelocitySensitivity: UInt8 = 0

    // MARK: Global pitch settings
    /// Octave transposition (-2 to +2)
    var octave: Int = 0

    // MARK: Modulation
    var vibrato: VZLFO = VZLFO()
    var tremolo: VZLFO = VZLFO()

    // MARK: Global key follow rate curve (affects how fast key follow reacts)
    var keyFollowRateCurve: VZKeyFollowCurve = VZKeyFollowCurve()

    // MARK: Master amplitude
    /// Overall output level (0–99)
    var masterLevel: UInt8 = 99

    // MARK: Convenience accessors

    /// Access a module by 1-based number (M1 = module(1))
    func module(_ number: Int) -> VZModule {
        precondition((1...8).contains(number), "Module number must be 1–8")
        return modules[number - 1]
    }

    mutating func setModule(_ number: Int, to newValue: VZModule) {
        precondition((1...8).contains(number))
        modules[number - 1] = newValue
    }

    /// Access line by letter ("A"–"D")
    func line(_ letter: String) -> VZLine? {
        lines.first { $0.id == letter }
    }
}
