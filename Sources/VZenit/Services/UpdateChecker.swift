// UpdateChecker.swift
// VZenit — lightweight "is a newer version available?" check against GitHub Releases.
//
// Fires once per launch (rate-limited to one check every 6 hours across launches).
// On hit, publishes an UpdateInfo so the UI can offer a link to the Releases page.
// Failures are silent — there's nothing the user can do about a missed check.

import Foundation
import os.log

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var availableUpdate: UpdateInfo?
    /// Set after a manual (menu-triggered) check completes with no update or an error.
    /// The banner already covers the "update available" case; this is for the silent cases.
    @Published var manualCheckMessage: String?

    private let logger = Logger(subsystem: "io.github.iraaron.VZenit", category: "UpdateChecker")
    private let releasesURL = URL(string: "https://api.github.com/repos/iraaron/VZenit/releases/latest")!
    private let lastCheckKey = "VZenitLastUpdateCheck"
    private let minCheckInterval: TimeInterval = 60 * 60 * 6  // 6 hours

    private init() {}

    /// Trigger a check if enough time has passed since the last one (called on launch).
    func checkIfDue() {
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < minCheckInterval {
            logger.debug("Skipping update check — last ran \(lastCheck)")
            return
        }
        Task { await self.check() }
    }

    /// Force a check regardless of rate limit, with user-visible feedback (called from Help menu).
    func checkManually() {
        Task { await self.check(triggeredManually: true) }
    }

    func check(triggeredManually: Bool = false) async {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        var request = URLRequest(url: releasesURL, timeoutInterval: 8)
        request.setValue("VZenit/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.warning("Update check non-200 response")
                if triggeredManually {
                    manualCheckMessage = "Couldn't reach the update server (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Try again later."
                }
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = Self.stripVPrefix(release.tag_name)

            if Self.compareVersions(latestVersion, Self.currentVersion) == .orderedDescending {
                availableUpdate = UpdateInfo(
                    version: latestVersion,
                    url: URL(string: release.html_url) ?? releasesURL
                )
                logger.info("Update available: \(latestVersion)")
                // No alert — the banner handles this case.
            } else {
                availableUpdate = nil
                if triggeredManually {
                    manualCheckMessage = "VZenit \(Self.currentVersion) is the latest version."
                }
            }
        } catch {
            logger.warning("Update check failed: \(error.localizedDescription)")
            if triggeredManually {
                manualCheckMessage = "Couldn't check for updates: \(error.localizedDescription)"
            }
        }
    }

    nonisolated static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    nonisolated static func stripVPrefix(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Numeric, dot-separated comparison. "0.0.10" > "0.0.2".
    nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsParts.count, rhsParts.count)
        for i in 0..<count {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
}

struct UpdateInfo: Equatable {
    let version: String
    let url: URL
}

private struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
}
