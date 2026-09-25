import SwiftUI

/// Pending links sent from the S42 browser extension.
struct DesktopInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PairSession.self) private var pairSession
    @Bindable private var inbox = DesktopInboxStore.shared
    var onPick: (DesktopInboxItem) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if inbox.pending.isEmpty {
                    ContentUnavailableView(
                        "Nothing from desktop",
                        systemImage: "desktopcomputer",
                        description: Text("Click S42 in Chrome or Safari to send a link here.")
                    )
                } else {
                    List {
                        ForEach(inbox.pending) { item in
                            Button {
                                onPick(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.displayTitle)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(item.url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(item.createdDate, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await inbox.consume(item, pairID: pairSession.pairID)
                                    }
                                } label: {
                                    Label("Dismiss", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background { AppCanvasBackground().ignoresSafeArea() }
            .navigationTitle("From desktop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await inbox.refresh(pairID: pairSession.pairID) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(inbox.isLoading)
                }
            }
            .task {
                await inbox.refresh(pairID: pairSession.pairID)
            }
        }
        .tint(Palette.brandBlue(colorScheme))
    }
}
