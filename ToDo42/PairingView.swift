import SwiftUI

struct PairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PairSession.self) private var session
    @State private var joinCode = ""
    @State private var errorText = ""
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if session.isPaired {
                    connected
                } else {
                    unpaired
                }
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if !session.statusMessage.isEmpty {
                    Text(session.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            .background(Palette.canvas(colorScheme).ignoresSafeArea())
            .navigationTitle("Pair phones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let code = session.inviteCode {
                    ShareSheet(text: CloudSync.shared.inviteText(code: code))
                }
            }
        }
        .tint(Palette.brandBlue(colorScheme))
    }

    private var unpaired: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share one list")
                .font(.title2.bold())
            Text("Invite Deena with a code. She installs ToDo 4 2 from TestFlight, then enters the code. Both phones must be signed in to iCloud.")
                .foregroundStyle(.secondary)

            Button {
                Task { await createInvite() }
            } label: {
                Label(session.inviteCode == nil ? "Invite Deena" : "Show my code", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isBusy)

            if let code = session.inviteCode {
                Text(code)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                Button("Send Deena the code") { showShare = true }
                    .frame(maxWidth: .infinity)
            }

            Divider()

            Text("I have a code")
                .font(.headline)
            TextField("6-digit code", text: $joinCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Button("Join Chris") {
                Task { await join() }
            }
            .buttonStyle(.bordered)
            .disabled(session.isBusy || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Phones are paired", systemImage: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(Palette.brandBlue(colorScheme))
            if let role = session.role {
                Text("This phone is \(role.displayName). Hearts and new items sync to \(role.partnerName).")
                    .foregroundStyle(.secondary)
            }
            if let code = session.inviteCode, session.role == .chris {
                Text("Invite code: \(code)")
                    .font(.headline)
                Button("Send the code again") { showShare = true }
            }
        }
    }

    private func createInvite() async {
        errorText = ""
        session.isBusy = true
        defer { session.isBusy = false }
        do {
            _ = try await CloudSync.shared.createInvite()
            showShare = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func join() async {
        errorText = ""
        session.isBusy = true
        defer { session.isBusy = false }
        do {
            try await CloudSync.shared.join(code: joinCode)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
