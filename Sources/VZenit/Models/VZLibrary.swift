// VZLibrary.swift
// VZenit — Casio VZ-1 / VZ-10M / VZ-8M Patch Editor for macOS
//
// Manages a collection of VZ voice patches with file-based persistence.
// Libraries are stored as JSON bundles; individual patches can be exported
// as raw .syx files for use with other tools.

import Foundation
import Combine

// MARK: - Library

/// A named, file-backed collection of VZVoicePatch entries.
struct VZLibraryMetadata: Codable {
    var version: Int    = 1
    var name: String    = "My Library"
    var created: Date   = Date()
    var modified: Date  = Date()
    var notes: String   = ""
}

struct VZLibraryFile: Codable {
    var metadata: VZLibraryMetadata
    var patches:  [VZVoicePatch]
}

// MARK: - Manager

/// Observable store for the active library. Persists to disk automatically.
@MainActor
final class VZLibraryManager: ObservableObject {

    // MARK: Published state

    @Published var patches:   [VZVoicePatch]    = []
    @Published var metadata:  VZLibraryMetadata = VZLibraryMetadata()
    @Published var fileURL:   URL?              = nil
    @Published var isDirty:   Bool              = false
    @Published var lastError: String?           = nil

    // MARK: - Query helpers

    var groups: [String] {
        Array(Set(patches.map(\.group))).sorted()
    }

    func patches(in group: String) -> [VZVoicePatch] {
        patches.filter { $0.group == group }
    }

    func patch(id: UUID) -> VZVoicePatch? {
        patches.first { $0.id == id }
    }

    // MARK: - CRUD

    func add(_ patch: VZVoicePatch) {
        patches.append(patch)
        markDirty()
    }

    func update(_ patch: VZVoicePatch) {
        guard let idx = patches.firstIndex(where: { $0.id == patch.id }) else { return }
        patches[idx] = patch
        markDirty()
    }

    func remove(id: UUID) {
        patches.removeAll { $0.id == id }
        markDirty()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        patches.move(fromOffsets: source, toOffset: destination)
        markDirty()
    }

    // MARK: - File operations

    func newLibrary(name: String = "New Library") {
        patches  = []
        metadata = VZLibraryMetadata(name: name)
        fileURL  = nil
        isDirty  = false
    }

    func open(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(VZLibraryFile.self, from: data)
        patches  = file.patches
        metadata = file.metadata
        fileURL  = url
        isDirty  = false
    }

    func save() throws {
        guard let url = fileURL else { throw VZLibraryError.noURL }
        try saveAs(to: url)
    }

    func saveAs(to url: URL) throws {
        metadata.modified = Date()
        let file = VZLibraryFile(metadata: metadata, patches: patches)
        let data = try JSONEncoder().encode(file)
        try data.write(to: url, options: .atomicWrite)
        fileURL = url
        isDirty = false
    }

    // MARK: - SysEx import / export

    /// Import all VZ voice patches from a raw .syx file (may contain multiple voices).
    func importSysEx(from url: URL) throws -> [VZVoicePatch] {
        let raw  = try [UInt8](Data(contentsOf: url))
        let msgs = VZSysEx.extractMessages(from: raw)
        var imported: [VZVoicePatch] = []
        for msg in msgs {
            if let patch = try? VZSysEx.decode(msg) {
                imported.append(patch)
            }
        }
        guard !imported.isEmpty else { throw VZLibraryError.noVoicesFound }
        imported.forEach { add($0) }
        return imported
    }

    /// Export a single patch to a .syx file.
    func exportSysEx(_ patch: VZVoicePatch, to url: URL, channel: UInt8 = 0) throws {
        let bytes = VZSysEx.encode(patch, channel: channel)
        try Data(bytes).write(to: url, options: .atomicWrite)
    }

    /// Export all patches in the library to a single .syx file.
    func exportAllSysEx(to url: URL, channel: UInt8 = 0) throws {
        let bytes = patches.flatMap { VZSysEx.encode($0, channel: channel) }
        try Data(bytes).write(to: url, options: .atomicWrite)
    }

    // MARK: - Private

    private func markDirty() {
        isDirty = true
    }
}

// MARK: - Errors

enum VZLibraryError: Error, LocalizedError {
    case noURL
    case noVoicesFound

    var errorDescription: String? {
        switch self {
        case .noURL:         return "No file URL. Use Save As first."
        case .noVoicesFound: return "No VZ voice patches found in the selected file."
        }
    }
}
