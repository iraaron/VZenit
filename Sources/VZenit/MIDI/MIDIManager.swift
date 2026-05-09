// MIDIManager.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS
//
// Wraps CoreMIDI for port management and VZ SysEx communication.
// Uses the legacy MIDIPacketList / MIDIReadProc API for broad macOS compatibility
// and straightforward SysEx byte handling.
//
// Requires the "com.apple.security.device.audio-input" entitlement (or
// "com.apple.security.device.usb" for USB-MIDI) in your .entitlements file.

import Foundation
import CoreMIDI
import Combine

// MARK: - Endpoint wrapper

/// A lightweight, Identifiable wrapper around a CoreMIDI endpoint reference.
struct MIDIEndpoint: Identifiable, Equatable, Hashable {
    let ref: MIDIEndpointRef
    let name: String

    var id: MIDIEndpointRef { ref }

    static func == (lhs: MIDIEndpoint, rhs: MIDIEndpoint) -> Bool { lhs.ref == rhs.ref }
    func hash(into hasher: inout Hasher) { hasher.combine(ref) }
}

// MARK: - Manager

/// Singleton that manages all MIDI I/O for VZenit.
///
/// Observe `$inputs`, `$outputs`, `$receivedPatch`, and `$status` from SwiftUI views.
/// Call `connect(input:)` and `connect(output:)` when the user selects a port.
@MainActor
final class MIDIManager: ObservableObject {

    static let shared = MIDIManager()

    // MARK: Published state

    @Published var inputs:  [MIDIEndpoint] = []
    @Published var outputs: [MIDIEndpoint] = []

    @Published var selectedInput:  MIDIEndpoint? = nil
    @Published var selectedOutput: MIDIEndpoint? = nil

    /// The most recently received and successfully decoded VZ voice patch.
    @Published var receivedPatch: VZVoicePatch? = nil

    @Published var status: String = "Idle"
    @Published var isReady: Bool = false

    // MARK: Callbacks (alternative to Combine if preferred)

    var onVoiceReceived:    ((VZVoicePatch) -> Void)?
    var onSysExBytesRaw:    (([UInt8]) -> Void)?

    // MARK: Private MIDI state

    private var client:     MIDIClientRef = 0
    private var inPort:     MIDIPortRef   = 0
    private var outPort:    MIDIPortRef   = 0

    /// Accumulates raw bytes between F0 and F7.
    private var sysexBuffer: [UInt8] = []
    private var inSysex = false

    // MARK: - Initialisation

    private init() {
        setupMIDI()
    }

    private func setupMIDI() {
        // Create MIDI client with a setup-change notification block.
        // Capture `self` weakly; the block may fire on any thread so dispatch to main.
        let status = MIDIClientCreateWithBlock("VZenit" as CFString, &client) { [weak self] notifPtr in
            let msgID = notifPtr.pointee.messageID
            if msgID == .msgSetupChanged || msgID == .msgObjectAdded || msgID == .msgObjectRemoved {
                DispatchQueue.main.async { self?.refreshEndpoints() }
            }
        }

        guard status == noErr else {
            self.status = "MIDI client error: \(status)"
            return
        }

        // Output port (simple, no callback needed)
        MIDIOutputPortCreate(client, "VZenit Out" as CFString, &outPort)

        // Input port — uses the legacy MIDIReadProc so that SysEx arrives as raw bytes
        // in MIDIPacketList, which is the simplest way to handle long SysEx.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        MIDIInputPortCreate(client, "VZenit In" as CFString, midiReadProc, selfPtr, &inPort)

        refreshEndpoints()
        isReady = true
        status  = "Ready"
    }

    // MARK: - Port management

    func refreshEndpoints() {
        let srcCount  = MIDIGetNumberOfSources()
        let dstCount  = MIDIGetNumberOfDestinations()

        inputs  = (0..<srcCount).compactMap  { makeEndpoint(MIDIGetSource($0)) }
        outputs = (0..<dstCount).compactMap  { makeEndpoint(MIDIGetDestination($0)) }

        // Keep selections if endpoint still exists
        if let sel = selectedInput,  !inputs.contains(sel)  { selectedInput  = nil }
        if let sel = selectedOutput, !outputs.contains(sel) { selectedOutput = nil }
    }

    private func makeEndpoint(_ ref: MIDIEndpointRef) -> MIDIEndpoint? {
        guard ref != 0 else { return nil }
        var prop: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &prop)
        let name = prop?.takeRetainedValue() as String? ?? "Unknown"
        return MIDIEndpoint(ref: ref, name: name)
    }

    // MARK: - Connect / disconnect

    func connect(input endpoint: MIDIEndpoint) {
        if let prev = selectedInput { MIDIPortDisconnectSource(inPort, prev.ref) }
        selectedInput = endpoint
        MIDIPortConnectSource(inPort, endpoint.ref, nil)
        status = "Input: \(endpoint.name)"
    }

    func disconnect(input endpoint: MIDIEndpoint) {
        MIDIPortDisconnectSource(inPort, endpoint.ref)
        if selectedInput == endpoint { selectedInput = nil }
    }

    func connect(output endpoint: MIDIEndpoint) {
        selectedOutput = endpoint
        status = "Output: \(endpoint.name)"
    }

    // MARK: - Send

    /// Send the voice patch to the currently selected MIDI output.
    func sendVoice(_ patch: VZVoicePatch, channel: UInt8 = 0) {
        guard let output = selectedOutput else {
            status = "No output selected"; return
        }
        let bytes = VZSysEx.encode(patch, channel: channel)
        sendRaw(bytes, to: output.ref)
        status = "Sent: \(patch.name)"
    }

    /// Request a voice dump from the synth (triggers synth to send its current patch).
    func requestVoiceDump(channel: UInt8 = 0) {
        guard let output = selectedOutput else {
            status = "No output selected"; return
        }
        sendRaw(VZSysEx.voiceDumpRequest(channel: channel), to: output.ref)
        status = "Requesting voice dump…"
    }

    func requestOperationDump(channel: UInt8 = 0) {
        guard let output = selectedOutput else { return }
        sendRaw(VZSysEx.operationDumpRequest(channel: channel), to: output.ref)
    }

    /// Send arbitrary raw bytes to a destination.
    func sendRaw(_ bytes: [UInt8], to destination: MIDIEndpointRef) {
        guard !bytes.isEmpty else { return }

        // MIDIPacketList has a fixed buffer — for SysEx up to ~65 KB we allocate dynamically.
        let bufferSize = max(1024, bytes.count + 64)
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        buffer.withUnsafeMutableBytes { rawBuf in
            let listPtr = rawBuf.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            var packet  = MIDIPacketListInit(listPtr)
            packet = MIDIPacketListAdd(listPtr, bufferSize, packet, 0, bytes.count, bytes)
            MIDISend(outPort, destination, listPtr)
        }
    }

    // MARK: - Receive (called from C read proc, then dispatched to main)

    fileprivate func handleIncomingBytes(_ bytes: [UInt8]) {
        for byte in bytes {
            if byte == 0xF0 {
                inSysex     = true
                sysexBuffer = [byte]
            } else if inSysex {
                sysexBuffer.append(byte)
                if byte == 0xF7 {
                    inSysex = false
                    let completed = sysexBuffer
                    sysexBuffer   = []
                    processCompletedSysEx(completed)
                }
            }
            // Non-SysEx bytes outside a SysEx frame are silently ignored for now;
            // add a general MIDI message handler here if you need note-on etc.
        }
    }

    private func processCompletedSysEx(_ bytes: [UInt8]) {
        onSysExBytesRaw?(bytes)

        guard VZSysEx.isVZVoiceSysEx(bytes) else { return }

        if let patch = try? VZSysEx.decode(bytes) {
            receivedPatch = patch
            onVoiceReceived?(patch)
            status = "Received: \(patch.name)"
        } else {
            status = "Received unrecognised VZ SysEx"
        }
    }

    // MARK: - Cleanup

    deinit {
        MIDIClientDispose(client)
    }
}

// MARK: - C-compatible read proc

/// CoreMIDI calls this on an internal thread. We bounce to main via the manager.
private let midiReadProc: MIDIReadProc = { packetListPtr, readProcRefCon, _ in
    guard let refCon = readProcRefCon else { return }
    let manager = Unmanaged<MIDIManager>.fromOpaque(refCon).takeUnretainedValue()

    // Collect all bytes from the packet list
    var bytes: [UInt8] = []
    var packet = packetListPtr.pointee.packet
    for _ in 0..<packetListPtr.pointee.numPackets {
        let count = Int(packet.length)
        withUnsafeBytes(of: packet.data) { ptr in
            bytes.append(contentsOf: ptr.prefix(count))
        }
        packet = MIDIPacketNext(&packet).pointee
    }

    // Dispatch to main actor
    let captured = bytes
    Task { @MainActor in
        manager.handleIncomingBytes(captured)
    }
}
