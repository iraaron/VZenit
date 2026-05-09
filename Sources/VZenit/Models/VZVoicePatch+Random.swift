// VZVoicePatch+Random.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS
//
// Constrained patch randomizer. Covers the timbre-shaping parts of a patch
// (module waveforms, detune, envelopes, line combination modes, LFO depths)
// and leaves the more "production" details (key-follow curves, key velocity
// curves, external-phase routing) at their conservative defaults.
//
// All ranges are picked to fit comfortably inside the wire-format bit widths,
// so any random patch survives a SysEx round-trip — verified by a property
// test in VZVoicePatchRandomTests.

import Foundation

extension VZVoicePatch {

    /// Generate a random patch using the supplied RNG.
    /// Generic over `RandomNumberGenerator` so tests can pass a seeded RNG for determinism.
    static func random<R: RandomNumberGenerator>(using rng: inout R) -> VZVoicePatch {
        var patch = VZVoicePatch()
        patch.name = "RANDOM \(Int.random(in: 100...999, using: &rng))"

        // Per-module randomization
        for i in 0..<8 {
            patch.modules[i].dco.waveform   = VZWaveform.allCases.randomElement(using: &rng)!
            patch.modules[i].dco.detuneNote = Int.random(in: -2...2, using: &rng)
            patch.modules[i].dco.detuneFine = Int.random(in: -32...32, using: &rng)
            patch.modules[i].dco.harmonic   = Int.random(in: 1...16, using: &rng)
            patch.modules[i].dco.fixedPitch = (Int.random(in: 0..<10, using: &rng) == 0)

            for s in 0..<8 {
                patch.modules[i].dca.envelope.steps[s].rate      = UInt8.random(in: 30...90, using: &rng)
                patch.modules[i].dca.envelope.steps[s].level     = UInt8.random(in: 0...99, using: &rng)
                patch.modules[i].dca.envelope.steps[s].isSustain = false
            }
            // Place exactly one sustain step (1...5 leaves room for a release tail)
            let sustainStep = Int.random(in: 1...5, using: &rng)
            patch.modules[i].dca.envelope.steps[sustainStep].isSustain = true
        }

        // Line combination — bias toward Mix (most musically forgiving)
        let linePool: [VZLineMode] = [.mix, .mix, .mix, .phase, .phase, .ring]
        for i in 0..<4 {
            patch.lines[i].mode = linePool.randomElement(using: &rng)!
        }

        // Subtle global modulation
        patch.vibrato.depth = UInt8.random(in: 0...20, using: &rng)
        patch.vibrato.rate  = UInt8.random(in: 30...80, using: &rng)
        patch.tremolo.depth = UInt8.random(in: 0...20, using: &rng)
        patch.tremolo.rate  = UInt8.random(in: 30...80, using: &rng)

        // DCO pitch envelope depth is a 6-bit field on the wire (0–63)
        patch.dcoPitchEnvelope.depth = UInt8.random(in: 0...20, using: &rng)

        // Audible master level
        patch.masterLevel = UInt8.random(in: 70...99, using: &rng)

        // Octave: mostly centred, occasional ±1
        patch.octave = [0, 0, 0, 0, -1, 1].randomElement(using: &rng)!

        return patch
    }

    /// Convenience using the system RNG.
    static func random() -> VZVoicePatch {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }
}
