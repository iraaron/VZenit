// VZSysExTests.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS
//
// Round-trip + framing + error-path coverage for the bit-accurate SysEx codec.
// These tests don't require any hardware — they validate that encode → decode
// is lossless and that malformed frames are rejected with the right error.

import XCTest
@testable import VZenit

final class VZSysExTests: XCTestCase {

    // MARK: - Dump request frames

    func testVoiceDumpRequestDefaultChannel() {
        let bytes = VZSysEx.voiceDumpRequest()
        XCTAssertEqual(bytes, [0xF0, 0x44, 0x00, 0x00, 0x80, 0xF7])
    }

    func testVoiceDumpRequestChannel5() {
        let bytes = VZSysEx.voiceDumpRequest(channel: 5)
        XCTAssertEqual(bytes, [0xF0, 0x44, 0x05, 0x00, 0x80, 0xF7])
    }

    func testVoiceDumpRequestChannelMaskedToLowerNibble() {
        let bytes = VZSysEx.voiceDumpRequest(channel: 0xFF)
        XCTAssertEqual(bytes[2], 0x0F)
    }

    func testOperationDumpRequest() {
        // operation cmd 0x60 | request prefix 0x10 = 0x70
        let bytes = VZSysEx.operationDumpRequest()
        XCTAssertEqual(bytes, [0xF0, 0x44, 0x00, 0x00, 0x70, 0xF7])
    }

    // MARK: - Encode framing

    func testEncodeProducesCorrectFrameLength() {
        let bytes = VZSysEx.encode(VZVoicePatch())
        XCTAssertEqual(bytes.count, VZSysEx.frameOverhead + VZSysEx.voiceDataLength)
    }

    func testEncodeProducesValidHeaderAndFooter() {
        let bytes = VZSysEx.encode(VZVoicePatch(), channel: 3)
        XCTAssertEqual(bytes[0], 0xF0)         // start
        XCTAssertEqual(bytes[1], 0x44)         // Casio manufacturer
        XCTAssertEqual(bytes[2], 0x03)         // channel
        XCTAssertEqual(bytes[3], 0x00)         // sub-ID
        XCTAssertEqual(bytes[4], 0x70)         // voice dump command
        XCTAssertEqual(bytes.last, 0xF7)       // end
    }

    func testIsVZVoiceSysExAcceptsEncodedPatch() {
        XCTAssertTrue(VZSysEx.isVZVoiceSysEx(VZSysEx.encode(VZVoicePatch())))
    }

    func testIsVZVoiceSysExRejectsGarbage() {
        XCTAssertFalse(VZSysEx.isVZVoiceSysEx([]))
        XCTAssertFalse(VZSysEx.isVZVoiceSysEx([0xF0, 0xF7]))
        // operation cmd, not voice
        XCTAssertFalse(VZSysEx.isVZVoiceSysEx([0xF0, 0x44, 0x00, 0x00, 0x60, 0xF7]))
        // a request frame is not a dump frame
        XCTAssertFalse(VZSysEx.isVZVoiceSysEx(VZSysEx.voiceDumpRequest()))
    }

    // MARK: - Round-trip

    func testEncodeIsIdempotentOnBytes() throws {
        // Sanity check: encode → decode → encode produces the same bytes regardless of
        // whether the model defaults match the wire format.
        let bytes1 = VZSysEx.encode(VZVoicePatch())
        let decoded = try VZSysEx.decode(bytes1)
        let bytes2 = VZSysEx.encode(decoded)
        XCTAssertEqual(bytes1, bytes2)
    }

    func testDefaultPatchRoundTripsToEqualStruct() throws {
        // The full-equality version of the round-trip: requires that VZVoicePatch's defaults
        // sit within the wire format's bit widths and match the canonical post-decode form
        // (e.g. envelope step at endStep is marked isEnd=true; dcoKeyFollowCurve values fit
        // in 6 bits; trailing spaces aren't part of the default name).
        let original = VZVoicePatch()
        var decoded = try VZSysEx.decode(VZSysEx.encode(original))
        // Runtime/library metadata that's not part of the 336-byte wire format.
        decoded.id = original.id
        decoded.description = original.description
        decoded.group = original.group
        XCTAssertEqual(decoded, original)
    }

    func testCustomNameRoundTrips() throws {
        var original = VZVoicePatch()
        original.name = "TEST PATCH  "
        let bytes = VZSysEx.encode(original)
        let decoded = try VZSysEx.decode(bytes)
        XCTAssertEqual(decoded.name.trimmingCharacters(in: .whitespaces),
                       "TEST PATCH")
    }

    func testEveryWaveformRoundTripsPerModule() throws {
        var original = VZVoicePatch()
        for (i, wave) in VZWaveform.allCases.enumerated() {
            original.modules[i % 8].dco.waveform = wave
        }
        let decoded = try VZSysEx.decode(VZSysEx.encode(original))
        for i in 0..<8 {
            XCTAssertEqual(decoded.modules[i].dco.waveform,
                           original.modules[i].dco.waveform,
                           "Module \(i + 1) waveform mismatch")
        }
    }

    func testOctaveRoundTrips() throws {
        for octave in -2...2 {
            var original = VZVoicePatch()
            original.octave = octave
            let decoded = try VZSysEx.decode(VZSysEx.encode(original))
            XCTAssertEqual(decoded.octave, octave, "octave \(octave)")
        }
    }

    func testMasterLevelRoundTrips() throws {
        for level: UInt8 in [0, 50, 99] {
            var original = VZVoicePatch()
            original.masterLevel = level
            let decoded = try VZSysEx.decode(VZSysEx.encode(original))
            XCTAssertEqual(decoded.masterLevel, level)
        }
    }

    func testLineModesRoundTrip() throws {
        var original = VZVoicePatch()
        original.lines[0].mode = .mix
        original.lines[1].mode = .phase
        original.lines[2].mode = .ring
        original.lines[3].mode = .mix
        let decoded = try VZSysEx.decode(VZSysEx.encode(original))
        for i in 0..<4 {
            XCTAssertEqual(decoded.lines[i].mode, original.lines[i].mode,
                           "Line \(i) mode")
        }
    }

    // MARK: - Stream extraction

    func testExtractMessagesFromConcatenatedStream() {
        let p1 = VZSysEx.encode(VZVoicePatch())
        let p2 = VZSysEx.encode(VZVoicePatch(), channel: 7)
        let messages = VZSysEx.extractMessages(from: p1 + p2)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0], p1)
        XCTAssertEqual(messages[1], p2)
    }

    func testExtractMessagesIgnoresBytesBetweenFrames() {
        let p1 = VZSysEx.encode(VZVoicePatch())
        let junk: [UInt8] = [0x90, 0x40, 0x7F]   // a stray note-on
        let messages = VZSysEx.extractMessages(from: junk + p1 + junk)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], p1)
    }

    func testExtractMessagesDropsUnclosedFrame() {
        let p1 = VZSysEx.encode(VZVoicePatch())
        let truncated = Array(p1.prefix(p1.count - 1))
        XCTAssertEqual(VZSysEx.extractMessages(from: truncated).count, 0)
    }

    // MARK: - Decode error cases

    func testDecodeEmptyThrowsTooShort() {
        XCTAssertThrowsError(try VZSysEx.decode([])) { error in
            guard case VZSysExError.tooShort = error else {
                return XCTFail("Expected tooShort, got \(error)")
            }
        }
    }

    func testDecodeWrongManufacturerThrowsBadHeader() {
        var bytes = VZSysEx.encode(VZVoicePatch())
        bytes[1] = 0x42
        XCTAssertThrowsError(try VZSysEx.decode(bytes)) { error in
            guard case VZSysExError.badHeader = error else {
                return XCTFail("Expected badHeader, got \(error)")
            }
        }
    }

    func testDecodeMissingTerminatorThrowsBadTerminator() {
        var bytes = VZSysEx.encode(VZVoicePatch())
        bytes[bytes.count - 1] = 0x00
        XCTAssertThrowsError(try VZSysEx.decode(bytes)) { error in
            guard case VZSysExError.badTerminator = error else {
                return XCTFail("Expected badTerminator, got \(error)")
            }
        }
    }

    func testDecodeUnknownCommandThrows() {
        var bytes = VZSysEx.encode(VZVoicePatch())
        bytes[4] = 0x77
        XCTAssertThrowsError(try VZSysEx.decode(bytes)) { error in
            guard case VZSysExError.unknownCommand(let cmd) = error else {
                return XCTFail("Expected unknownCommand, got \(error)")
            }
            XCTAssertEqual(cmd, 0x77)
        }
    }
}
