// VZSysEx.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS
//
// Encodes and decodes the Casio VZ series SysEx wire format.
//
// SysEx frame structure:
//   F0  44  CH  00  CMD  [data bytes]  F7
//
//   F0  = SysEx start
//   44  = Casio manufacturer ID
//   CH  = device/channel (0x00–0x0F for channels 1–16)
//   00  = sub-ID (fixed)
//   CMD = 0x70 voice data | 0x60 operation data | 0x10|CMD for dump request
//
// Voice data is exactly 336 bytes (offsets documented inline and cross-referenced
// against "VZ sound creation.txt" in the riban-bw/vzeditor repository).

import Foundation

enum VZSysExError: Error, LocalizedError {
    case tooShort
    case badHeader
    case badTerminator
    case unknownCommand(UInt8)
    case dataTruncated(expected: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case .tooShort:                      return "SysEx message is too short."
        case .badHeader:                     return "Not a valid Casio VZ SysEx message."
        case .badTerminator:                 return "SysEx message missing F7 terminator."
        case .unknownCommand(let cmd):       return "Unknown VZ SysEx command: \(String(format: "%02X", cmd))."
        case .dataTruncated(let e, let g):  return "Data truncated: expected \(e) bytes, got \(g)."
        }
    }
}

struct VZSysEx {

    // MARK: - Constants

    static let startByte: UInt8    = 0xF0
    static let manufacturerID: UInt8 = 0x44   // Casio
    static let subID: UInt8        = 0x00
    static let endByte: UInt8      = 0xF7

    static let cmdVoice: UInt8     = 0x70   // Voice bulk dump
    static let cmdOperation: UInt8 = 0x60   // Operation bulk dump
    static let cmdRequest: UInt8   = 0x10   // Dump request prefix

    static let voiceDataLength     = 336
    static let headerLength        = 5      // F0 44 CH 00 CMD
    static let frameOverhead       = 6      // header (5) + F7 (1)

    // MARK: - Frame helpers

    /// Build a dump-request frame (sent to synth to trigger a voice dump)
    static func voiceDumpRequest(channel: UInt8 = 0) -> [UInt8] {
        [startByte, manufacturerID, channel & 0x0F, subID, cmdRequest | cmdVoice, endByte]
    }

    static func operationDumpRequest(channel: UInt8 = 0) -> [UInt8] {
        [startByte, manufacturerID, channel & 0x0F, subID, cmdRequest | cmdOperation, endByte]
    }

    // MARK: - Decode

    /// Parse a raw SysEx byte array (including F0 … F7 wrapper) into a VZVoicePatch.
    static func decode(_ sysex: [UInt8]) throws -> VZVoicePatch {
        guard sysex.count >= frameOverhead else { throw VZSysExError.tooShort }
        guard sysex[0] == startByte,
              sysex[1] == manufacturerID,
              sysex[3] == subID else { throw VZSysExError.badHeader }
        guard sysex.last == endByte else { throw VZSysExError.badTerminator }

        let cmd = sysex[4]
        guard cmd == cmdVoice else { throw VZSysExError.unknownCommand(cmd) }

        let dataStart = headerLength
        let dataEnd   = sysex.count - 1  // exclude F7
        let data      = Array(sysex[dataStart..<dataEnd])

        guard data.count >= voiceDataLength else {
            throw VZSysExError.dataTruncated(expected: voiceDataLength, got: data.count)
        }

        return try decodeVoiceData(data)
    }

    /// Parse raw 336-byte voice data (no SysEx wrapper).
    static func decodeVoiceData(_ data: [UInt8]) throws -> VZVoicePatch {
        guard data.count >= voiceDataLength else {
            throw VZSysExError.dataTruncated(expected: voiceDataLength, got: data.count)
        }

        var p = VZVoicePatch()

        // ── Byte 0 ─────────────────────────────────────────────────────────────
        // Bits F,G,H (2,1,0): external phase enable for M4, M6, M8
        p.lines[1].externalPhase = data[0].bit(2)  // Line B / M4
        p.lines[2].externalPhase = data[0].bit(1)  // Line C / M6
        p.lines[3].externalPhase = data[0].bit(0)  // Line D / M8

        // ── Bytes 1–4 ──────────────────────────────────────────────────────────
        // Each byte encodes one line (A–D):
        //   Bits 7–6 = line mode (0=Mix, 1=Phase, 2=Ring)
        //   Bits 5–3 = even (carrier) module waveform
        //   Bits 2–0 = odd  (modulator) module waveform
        for lineIdx in 0..<4 {
            let b = data[1 + lineIdx]
            p.lines[lineIdx].mode        = VZLineMode(rawValue: (b >> 6) & 0x03) ?? .mix
            let carrierIdx  = lineIdx * 2 + 1   // M2, M4, M6, M8 (0-based index)
            let modulatorIdx = lineIdx * 2       // M1, M3, M5, M7
            p.modules[carrierIdx].dco.waveform  = VZWaveform(rawValue: (b >> 3) & 0x07) ?? .sine
            p.modules[modulatorIdx].dco.waveform = VZWaveform(rawValue: b & 0x07) ?? .sine
        }

        // ── Bytes 5–20: DCO pitch settings (2 bytes × 8 modules) ───────────────
        // Byte N+0:  bits 7–2 = fine detune (signed 6-bit), bit 1 = fixed pitch, bit 0 = range
        // Byte N+1:  bit 7 = detune polarity (1=positive), bits 6–0 = detune note
        for modIdx in 0..<8 {
            let base = 5 + modIdx * 2
            let b0 = data[base], b1 = data[base + 1]

            let rawFine = Int((b0 >> 2) & 0x3F)
            p.modules[modIdx].dco.detuneFine  = rawFine > 31 ? rawFine - 64 : rawFine
            p.modules[modIdx].dco.fixedPitch  = b0.bit(1)

            let noteSign = b1.bit(7) ? 1 : -1
            p.modules[modIdx].dco.detuneNote  = noteSign * Int(b1 & 0x7F)
        }

        // ── Bytes 21–163: Envelope data ─────────────────────────────────────────
        // Layout for each of 8 steps:
        //   Offset 0  : M1 DCA rate
        //   Offset 1–7: M2–M8 DCA rates
        //   Offset 8  : DCO pitch envelope rate
        //   Offset 9  : M1 DCA level  (bit 7 = sustain point, bits 6–0 = level)
        //   Offset 10–16: M2–M8 DCA levels
        //   Offset 17 : DCO pitch envelope level
        //   — total 18 bytes per step × 8 steps = 144 bytes (offsets 21–164)
        for step in 0..<8 {
            let base = 21 + step * 18

            for modIdx in 0..<8 {
                let rateByte  = data[base + modIdx]
                let levelByte = data[base + 9 + modIdx]
                p.modules[modIdx].dca.envelope.steps[step] = VZEnvelopeStep(
                    rate:      rateByte & 0x7F,
                    level:     levelByte & 0x7F,
                    isSustain: levelByte.bit(7),
                    isEnd:     false
                )
            }

            let dcoRate  = data[base + 8]
            let dcoLevel = data[base + 17]
            p.dcoPitchEnvelope.steps[step] = VZEnvelopeStep(
                rate:      dcoRate & 0x7F,
                level:     dcoLevel & 0x7F,
                isSustain: dcoLevel.bit(7),
                isEnd:     false
            )
        }

        // ── Bytes 165–172: DCA end step + amplitude sensitivity ─────────────────
        // Bits 6–4 = envelope end step (0–7), bits 2–0 = amp sensitivity (0–7)
        for modIdx in 0..<8 {
            let b = data[165 + modIdx]
            let endStep = (b >> 4) & 0x07
            p.modules[modIdx].dca.envelope.endStep = endStep
            if Int(endStep) < 8 { p.modules[modIdx].dca.envelope.steps[Int(endStep)].isEnd = true }
            p.modules[modIdx].dca.ampSensitivity = b & 0x07
        }

        // ── Byte 173: DCO envelope end step ────────────────────────────────────
        let dcoEndStep = (data[173] >> 4) & 0x07
        p.dcoPitchEnvelope.endStep = dcoEndStep
        if Int(dcoEndStep) < 8 { p.dcoPitchEnvelope.steps[Int(dcoEndStep)].isEnd = true }

        // ── Byte 174: Master level  [0x00–0x7F maps to 99–0] ──────────────────
        p.masterLevel = UInt8(clamping: 99 - Int(data[174] & 0x7F))

        // ── Bytes 175–182: Module on/off + DCA envelope depth ──────────────────
        // Bit 7 = module enabled; bits 6–0 = envelope depth
        for modIdx in 0..<8 {
            let b = data[175 + modIdx]
            p.modules[modIdx].enabled             = b.bit(7)
            p.modules[modIdx].dca.envelope.depth  = b & 0x7F
        }

        // ── Byte 183: DCO range flag + DCO envelope depth ──────────────────────
        p.dcoPitchEnvelopeRange     = data[183].bit(7)
        p.dcoPitchEnvelope.depth    = data[183] & 0x3F

        // ── Bytes 184–279: DCA key follow curves (8 modules × 6 steps × 2 bytes) ─
        for modIdx in 0..<8 {
            let mBase = 184 + modIdx * 12
            for step in 0..<6 {
                p.modules[modIdx].dca.keyFollowCurve.points[step] = VZKeyFollowPoint(
                    key:   data[mBase + step * 2]     & 0x7F,
                    value: data[mBase + step * 2 + 1] & 0x7F
                )
            }
        }

        // ── Bytes 280–291: DCO key follow curve (6 steps × 2 bytes) ───────────
        for step in 0..<6 {
            p.dcoKeyFollowCurve.points[step] = VZKeyFollowPoint(
                key:   data[280 + step * 2]     & 0x7F,
                value: data[281 + step * 2]     & 0x3F
            )
        }

        // ── Bytes 292–303: Global key-follow rate curve (6 steps × 2 bytes) ───
        for step in 0..<6 {
            p.keyFollowRateCurve.points[step] = VZKeyFollowPoint(
                key:   data[292 + step * 2]     & 0x7F,
                value: data[293 + step * 2]     & 0x7F
            )
        }

        // ── Bytes 304–311: Per-module key velocity curve + sensitivity ──────────
        // Bits 7–5 = curve (0–7); bits 4–0 = sensitivity (0–31)
        for modIdx in 0..<8 {
            let b = data[304 + modIdx]
            p.modules[modIdx].dca.keyVelocityCurve        = (b >> 5) & 0x07
            p.modules[modIdx].dca.keyVelocitySensitivity  = b & 0x1F
        }

        // ── Byte 312: DCO key velocity ──────────────────────────────────────────
        p.dcoKeyVelocityCurve       = (data[312] >> 5) & 0x07
        p.dcoKeyVelocitySensitivity = data[312] & 0x1F

        // ── Byte 314: Octave + vibrato multi + vibrato waveform ─────────────────
        // Bit 7 = octave polarity, bits 6–5 = octave magnitude, bit 3 = vibrato multi,
        // bits 1–0 = vibrato waveform
        let b314 = data[314]
        let octSign = b314.bit(7) ? 1 : -1
        p.octave = octSign * Int((b314 >> 5) & 0x03)
        p.vibrato.multiMode  = b314.bit(3)
        p.vibrato.waveform   = VZLFOWaveform(rawValue: b314 & 0x03) ?? .triangle

        p.vibrato.depth = data[315] & 0x7F
        p.vibrato.rate  = data[316] & 0x7F
        p.vibrato.delay = data[317] & 0x7F

        // ── Byte 318: Tremolo multi + waveform ─────────────────────────────────
        let b318 = data[318]
        p.tremolo.multiMode = b318.bit(3)
        p.tremolo.waveform  = VZLFOWaveform(rawValue: b318 & 0x03) ?? .triangle

        p.tremolo.depth = data[319] & 0x7F
        p.tremolo.rate  = data[320] & 0x7F
        p.tremolo.delay = data[321] & 0x7F

        // ── Bytes 322–333: Voice name (12 ASCII bytes, space-padded) ───────────
        let nameBytes = Array(data[322..<334])
        p.name = String(bytes: nameBytes, encoding: .ascii)?
            .trimmingCharacters(in: .init(charactersIn: "\0 ")) ?? "NO NAME"

        return p
    }

    // MARK: - Encode

    /// Encode a VZVoicePatch into a complete SysEx frame (F0 … F7).
    static func encode(_ patch: VZVoicePatch, channel: UInt8 = 0) -> [UInt8] {
        var data = [UInt8](repeating: 0x00, count: voiceDataLength)
        encodeVoiceData(patch, into: &data)
        return [startByte, manufacturerID, channel & 0x0F, subID, cmdVoice] + data + [endByte]
    }

    /// Fill a pre-allocated 336-byte buffer with the encoded voice parameters.
    static func encodeVoiceData(_ patch: VZVoicePatch, into data: inout [UInt8]) {
        precondition(data.count >= voiceDataLength)

        // ── Byte 0: external phase ──────────────────────────────────────────────
        data[0] = 0
        if patch.lines[1].externalPhase { data[0] |= 0x04 }
        if patch.lines[2].externalPhase { data[0] |= 0x02 }
        if patch.lines[3].externalPhase { data[0] |= 0x01 }

        // ── Bytes 1–4: line modes + waveforms ──────────────────────────────────
        for lineIdx in 0..<4 {
            let carrierIdx   = lineIdx * 2 + 1
            let modulatorIdx = lineIdx * 2
            var b: UInt8 = 0
            b |= (patch.lines[lineIdx].mode.rawValue & 0x03) << 6
            b |= (patch.modules[carrierIdx].dco.waveform.rawValue  & 0x07) << 3
            b |= (patch.modules[modulatorIdx].dco.waveform.rawValue & 0x07)
            data[1 + lineIdx] = b
        }

        // ── Bytes 5–20: DCO pitch settings ─────────────────────────────────────
        for modIdx in 0..<8 {
            let base = 5 + modIdx * 2
            let dco  = patch.modules[modIdx].dco

            let fine6bit = UInt8(bitPattern: Int8(clamping: dco.detuneFine)) & 0x3F
            var b0: UInt8 = fine6bit << 2
            if dco.fixedPitch { b0 |= 0x02 }
            data[base] = b0

            let sign: UInt8 = dco.detuneNote >= 0 ? 0x80 : 0x00
            data[base + 1] = sign | (UInt8(clamping: abs(dco.detuneNote)) & 0x7F)
        }

        // ── Bytes 21–163: Envelope data ─────────────────────────────────────────
        for step in 0..<8 {
            let base = 21 + step * 18
            for modIdx in 0..<8 {
                let s = patch.modules[modIdx].dca.envelope.steps[step]
                data[base + modIdx]     = s.rate & 0x7F
                var lb: UInt8 = s.level & 0x7F
                if s.isSustain { lb |= 0x80 }
                data[base + 9 + modIdx] = lb
            }
            let ds = patch.dcoPitchEnvelope.steps[step]
            data[base + 8]  = ds.rate & 0x7F
            var dlb: UInt8  = ds.level & 0x7F
            if ds.isSustain { dlb |= 0x80 }
            data[base + 17] = dlb
        }

        // ── Bytes 165–172: DCA end step + amp sensitivity ──────────────────────
        for modIdx in 0..<8 {
            let dca = patch.modules[modIdx].dca
            data[165 + modIdx] = ((dca.envelope.endStep & 0x07) << 4) | (dca.ampSensitivity & 0x07)
        }

        // ── Byte 173: DCO envelope end step ────────────────────────────────────
        data[173] = (patch.dcoPitchEnvelope.endStep & 0x07) << 4

        // ── Byte 174: Master level ──────────────────────────────────────────────
        data[174] = UInt8(clamping: 99 - Int(min(patch.masterLevel, 99))) & 0x7F

        // ── Bytes 175–182: Module on/off + DCA depth ───────────────────────────
        for modIdx in 0..<8 {
            let mod = patch.modules[modIdx]
            var b: UInt8 = mod.dca.envelope.depth & 0x7F
            if mod.enabled { b |= 0x80 }
            data[175 + modIdx] = b
        }

        // ── Byte 183: DCO range + depth ────────────────────────────────────────
        var b183: UInt8 = patch.dcoPitchEnvelope.depth & 0x3F
        if patch.dcoPitchEnvelopeRange { b183 |= 0x80 }
        data[183] = b183

        // ── Bytes 184–279: DCA key follow ──────────────────────────────────────
        for modIdx in 0..<8 {
            let mBase = 184 + modIdx * 12
            for step in 0..<6 {
                let pt = patch.modules[modIdx].dca.keyFollowCurve.points[step]
                data[mBase + step * 2]     = pt.key   & 0x7F
                data[mBase + step * 2 + 1] = pt.value & 0x7F
            }
        }

        // ── Bytes 280–291: DCO key follow ──────────────────────────────────────
        for step in 0..<6 {
            let pt = patch.dcoKeyFollowCurve.points[step]
            data[280 + step * 2] = pt.key   & 0x7F
            data[281 + step * 2] = pt.value & 0x3F
        }

        // ── Bytes 292–303: Global key-follow rate curve ─────────────────────────
        for step in 0..<6 {
            let pt = patch.keyFollowRateCurve.points[step]
            data[292 + step * 2] = pt.key   & 0x7F
            data[293 + step * 2] = pt.value & 0x7F
        }

        // ── Bytes 304–311: Per-module key velocity ──────────────────────────────
        for modIdx in 0..<8 {
            let dca = patch.modules[modIdx].dca
            data[304 + modIdx] = ((dca.keyVelocityCurve & 0x07) << 5) | (dca.keyVelocitySensitivity & 0x1F)
        }

        // ── Byte 312: DCO key velocity ──────────────────────────────────────────
        data[312] = ((patch.dcoKeyVelocityCurve & 0x07) << 5) | (patch.dcoKeyVelocitySensitivity & 0x1F)

        // ── Byte 314: Octave + vibrato ──────────────────────────────────────────
        var b314: UInt8 = 0
        if patch.octave >= 0 { b314 |= 0x80 }
        b314 |= (UInt8(clamping: abs(patch.octave)) & 0x03) << 5
        if patch.vibrato.multiMode { b314 |= 0x08 }
        b314 |= patch.vibrato.waveform.rawValue & 0x03
        data[314] = b314
        data[315]  = patch.vibrato.depth & 0x7F
        data[316]  = patch.vibrato.rate  & 0x7F
        data[317]  = patch.vibrato.delay & 0x7F

        // ── Byte 318: Tremolo ───────────────────────────────────────────────────
        var b318: UInt8 = 0
        if patch.tremolo.multiMode { b318 |= 0x08 }
        b318 |= patch.tremolo.waveform.rawValue & 0x03
        data[318] = b318
        data[319]  = patch.tremolo.depth & 0x7F
        data[320]  = patch.tremolo.rate  & 0x7F
        data[321]  = patch.tremolo.delay & 0x7F

        // ── Bytes 322–333: Voice name (12 bytes, space-padded) ─────────────────
        let nameBytes = Array(patch.name.prefix(12).utf8)
        for i in 0..<12 {
            data[322 + i] = i < nameBytes.count ? nameBytes[i] : 0x20
        }
        // Bytes 334–335: unused, leave as 0x00
    }

    // MARK: - SysEx stream scanner

    /// Scan a raw byte stream and extract all complete VZ SysEx messages.
    /// Use this when accumulating bytes from a CoreMIDI input port.
    static func extractMessages(from stream: [UInt8]) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        var current: [UInt8] = []
        var inSysex = false

        for byte in stream {
            if byte == startByte {
                inSysex = true
                current = [byte]
            } else if byte == endByte && inSysex {
                current.append(byte)
                messages.append(current)
                current = []
                inSysex = false
            } else if inSysex {
                current.append(byte)
            }
        }
        return messages
    }

    /// Returns true if this looks like a VZ voice SysEx frame (before full decode).
    static func isVZVoiceSysEx(_ bytes: [UInt8]) -> Bool {
        bytes.count >= frameOverhead
            && bytes[0] == startByte
            && bytes[1] == manufacturerID
            && bytes[3] == subID
            && bytes[4] == cmdVoice
            && bytes.last == endByte
    }
}

// MARK: - UInt8 bit helpers

private extension UInt8 {
    /// Returns true if the given bit (0 = LSB, 7 = MSB) is set.
    func bit(_ position: Int) -> Bool {
        (self >> position) & 0x01 == 1
    }
}
