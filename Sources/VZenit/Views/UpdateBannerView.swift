// UpdateBannerView.swift
// VZenit — banner shown when a newer release is available on GitHub.

import SwiftUI

struct UpdateBannerView: View {
    let update: UpdateInfo
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            Text("VZenit \(update.version) is available")
                .font(.callout)
            Spacer()
            Button("Open Releases") {
                NSWorkspace.shared.open(update.url)
            }
            .buttonStyle(.borderless)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Dismiss for this session")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.12))
    }
}
