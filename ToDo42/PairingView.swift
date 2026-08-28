import SwiftUI
import SwiftData

struct PairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(PairSession.self) private var session
    @Query private var items: [TodoItem]
    @State private var joinCode = ""
    @State private var errorText = ""
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameFields
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
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
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
            .onDisappear {
                session.persist()
            }
        }
        .tint(Palette.brandBlue(colorScheme))
    }

    private var nameFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Names")
                .font(.title2.bold())
            Text("These show on hearts and in notifications.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Your name", text: myNameBinding)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)
            TextField("Partner’s name", text: partnerNameBinding)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var myNameBinding: Binding<String> {
        Binding(
            get: { session.myName },
            set: { session.myName = $0 }
        )
    }

    private var partnerNameBinding: Binding<String> {
        Binding(
            get: { session.partnerName },
            set: { session.partnerName = $0 }
        )
    }

    private var unpaired: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share one list")
                .font(.title2.bold())
            Text("Invite \(session.partnerHeartLabel) with a code. They install Save4Two from TestFlight, then enter the code. Both phones must be signed in to iCloud.")
                .foregroundStyle(.secondary)

            Button {
                Task { await createInvite() }
            } label: {
                Label(
                    session.inviteCode == nil ? "Invite \(session.partnerHeartLabel)" : "Show my code",
                    systemImage: "person.badge.plus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isBusy || !session.hasNames)

            if let code = session.inviteCode {
                Text(code)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                Button("Send \(session.partnerHeartLabel) the code") { showShare = true }
                    .frame(maxWidth: .infinity)
            }

            Divider()

            Text("I have a code")
                .font(.headline)
            TextField("6-digit code", text: $joinCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Button("Join \(session.partnerHeartLabel)") {
                Task { await join() }
            }
            .buttonStyle(.bordered)
            .disabled(session.isBusy || !session.hasNames || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Phones are paired", systemImage: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(Palette.brandBlue(colorScheme))
            Text("This phone is \(session.myHeartLabel). Hearts and new items sync to \(session.partnerHeartLabel).")
                .foregroundStyle(.secondary)
            if let code = session.inviteCode, session.role == .chris {
                Text("Invite code: \(code)")
                    .font(.headline)
                Button("Send the code again") { showShare = true }
                Button("New invite code") {
                    Task { await createInvite() }
                }
                .disabled(session.isBusy || !session.hasNames)
            }
            Button("Unpair phones") {
                session.unpair()
            }
            .foregroundStyle(.secondary)
        }
    }

    private func createInvite() async {
        errorText = ""
        session.isBusy = true
        defer { session.isBusy = false }
        session.persistLocal()
        do {
            _ = try await CloudSync.shared.createInvite()
            await CloudSync.shared.sync(modelContext: modelContext, items: items)
            showShare = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func join() async {
        errorText = ""
        session.isBusy = true
        defer { session.isBusy = false }
        session.persistLocal()
        do {
            try await CloudSync.shared.join(code: joinCode)
            await CloudSync.shared.sync(modelContext: modelContext, items: items)
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
