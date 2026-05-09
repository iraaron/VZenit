// VZVoicePatchRandomTests.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS

import XCTest
@testable import VZenit

final class VZVoicePatchRandomTests: XCTestCase {

    /// Deterministic linear-congruential RNG for reproducible randomization in tests.
    /// Knuth's MMIX constants. Not cryptographically strong; perfectly fine for test fixtures.
    struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed | 1 }   // |1 avoids the zero fixed point
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    // MARK: - Determinism

    func testSameSeedProducesSamePatch() {
        var rng1 = SeededRNG(seed: 42)
        var rng2 = SeededRNG(seed: 42)
        let p1 = VZVoicePatch.random(using: &rng1)
        let p2 = VZVoicePatch.random(using: &rng2)
        // VZVoicePatch.id is freshly UUID'd each time; compare wire-relevant fields
        XCTAssertEqual(p1.modules,     p2.modules)
        XCTAssertEqual(p1.lines,       p2.lines)
        XCTAssertEqual(p1.vibrato,     p2.vibrato)
        XCTAssertEqual(p1.tremolo,     p2.tremolo)
        XCTAssertEqual(p1.masterLevel, p2.masterLevel)
        XCTAssertEqual(p1.octave,      p2.octave)
    }

    func testDifferentSeedsProduceDifferentPatches() {
        var rng1 = SeededRNG(seed: 1)
        var rng2 = SeededRNG(seed: 2)
        XCTAssertNotEqual(VZVoicePatch.random(using: &rng1).modules,
                          VZVoicePatch.random(using: &rng2).modules)
    }

    // MARK: - Property: every random patch survives the SysEx round-trip

    func testRandomPatchesAreEncodableLosslessly() throws {
        for seed: UInt64 in [1, 17, 42, 100, 256, 1024, 9999, 65535, 1_000_000] {
            var rng = SeededRNG(seed: seed)
            let original = VZVoicePatch.random(using: &rng)
            let bytes1   = VZSysEx.encode(original)
            let decoded  = try VZSysEx.decode(bytes1)
            let bytes2   = VZSysEx.encode(decoded)
            XCTAssertEqual(bytes1, bytes2,
                           "Random patch with seed \(seed) is not byte-idempotent — randomizer produced an out-of-range value")
        }
    }

    // MARK: - Sanity invariants

    func testRandomPatchHasExactlyOneSustainPerEnvelope() {
        var rng = SeededRNG(seed: 12345)
        let patch = VZVoicePatch.random(using: &rng)
        for module in patch.modules {
            let sustainCount = module.dca.envelope.steps.filter(\.isSustain).count
            XCTAssertEqual(sustainCount, 1, "Module \(module.id) should have exactly one sustain step")
        }
    }

    func testRandomPatchMasterLevelStaysAudible() {
        for seed: UInt64 in [1, 100, 500, 1000, 5000] {
            var rng = SeededRNG(seed: seed)
            let patch = VZVoicePatch.random(using: &rng)
            XCTAssertGreaterThanOrEqual(patch.masterLevel, 70)
            XCTAssertLessThanOrEqual(patch.masterLevel, 99)
        }
    }

    func testRandomPatchNameStartsWithRANDOM() {
        var rng = SeededRNG(seed: 7)
        XCTAssertTrue(VZVoicePatch.random(using: &rng).name.hasPrefix("RANDOM"))
    }
}
