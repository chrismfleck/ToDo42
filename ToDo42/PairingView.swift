import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct PairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(PairSession.self) private var session
    @State private var joinCode = ""
    @State private var restoreCode = ""
    @State private var errorText = ""
    @State private var showShare = false
    @State private var myHeadPicker: PhotosPickerItem?
    @State private var partnerHeadPicker: PhotosPickerItem?
    @Bindable private var desktopInbox = DesktopInboxStore.shared

    private var showInviteJoin: Bool {
        !session.isPaired || session.isComposingNewPair
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    hero
                    if !session.savedPairs.isEmpty {
                        pairsListCard
                    }
                    namesCard
                    if session.isPaired, !session.isComposingNewPair {
                        connectedCard
                        desktopLinkCard
                    }
                    if showInviteJoin {
                        inviteCard
                        orDivider
                        joinCard
                    }
                    restoreCard
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                    if !session.statusMessage.isEmpty {
                        Text(session.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    Link(destination: URL(string: "https://save4two.com")!) {
                        Text("save4two.com")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .accessibilityLabel("Open save4two.com")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AppCanvasBackground().ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showShare) {
                if let code = session.inviteCode {
                    ShareSheet(text: CloudSync.shared.inviteText(code: code))
                }
            }
            .onDisappear {
                if session.isComposingNewPair {
                    session.cancelComposePair()
                }
                session.persist()
            }
        }
        .tint(Palette.brandBlue(colorScheme))
    }

    private var header: some View {
        HStack {
            Button("Close") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(pillFill, in: Capsule())
            Spacer()
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    PairBrandMark()
                    Text("Save 4 Two")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(session.isComposingNewPair ? "Add a pair" : "Pair phones")
                    .font(.title2.bold())
                Text(
                    session.isComposingNewPair
                        ? "Start a separate list with someone else. Your other pairs stay as they are."
                        : "Share your list with someone you trust. Both phones must be signed in to iCloud."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            PairPhonesArt()
                .frame(width: 118, height: 100)
                .accessibilityHidden(true)
        }
        .padding(.top, 2)
    }

    private var pairsListCard: some View {
        pairCard {
            cardTitle("Your pairs", icon: "person.2.fill", tint: Color(red: 0.20, green: 0.48, blue: 0.98))
            Text("Open a list, or add another partner. Unpair removes only that pair.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(session.savedPairs) { profile in
                let isActive = profile.pairID == session.pairID && !session.isComposingNewPair
                Button {
                    session.switchToPair(profile.pairID)
                    Task { await CloudSync.shared.sync(modelContext: modelContext, allowCreate: false) }
                } label: {
                    HStack(spacing: 10) {
                        PairHeadAvatar(
                            label: profile.partnerName.isEmpty ? "Partner" : profile.partnerName,
                            tint: Color(red: 0.22, green: 0.78, blue: 0.55),
                            isActive: isActive,
                            imageData: session.headImageData(slot: .partner, pairID: profile.pairID)
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.partnerName.isEmpty ? "Partner" : profile.partnerName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(isActive ? "Open now" : "Tap to open")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.brandBlue(colorScheme))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
            }
            if session.isPaired, !session.isComposingNewPair {
                Button {
                    session.beginAddPair()
                    errorText = ""
                } label: {
                    Label("Add a pair", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Palette.brandBlue(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
            }
            if session.isComposingNewPair {
                Button("Cancel adding a pair") {
                    session.cancelComposePair()
                    errorText = ""
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var namesCard: some View {
        pairCard {
            cardTitle("Add names", number: 1, icon: "person.fill", tint: Color(red: 0.20, green: 0.48, blue: 0.98))
            Text("These show on hearts and notifications. Tap a head to add a photo.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                editableHead(
                    slot: .me,
                    label: session.myHeartLabel,
                    tint: Color(red: 0.20, green: 0.48, blue: 0.98),
                    picker: $myHeadPicker
                )
                pairField("Your name", text: myNameBinding)
            }
            HStack(spacing: 10) {
                editableHead(
                    slot: .partner,
                    label: session.partnerHeartLabel,
                    tint: Color(red: 0.22, green: 0.78, blue: 0.55),
                    picker: $partnerHeadPicker
                )
                pairField(
                    session.isComposingNewPair ? "Second Partner’s name" : "Partner’s name",
                    text: partnerNameBinding
                )
            }
        }
    }

    private func editableHead(
        slot: PairHeadPhotos.Slot,
        label: String,
        tint: Color,
        picker: Binding<PhotosPickerItem?>
    ) -> some View {
        PhotosPicker(selection: picker, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                PairHeadAvatar(
                    label: label,
                    tint: tint,
                    size: 44,
                    imageData: session.headImageData(slot: slot)
                )
                Image(systemName: "camera.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Palette.brandBlue(colorScheme), in: Circle())
                    .offset(x: 2, y: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slot == .me ? "Your photo" : "Partner photo")
        .onChange(of: picker.wrappedValue) { _, item in
            Task { await applyHeadPick(item, slot: slot, picker: picker) }
        }
    }

    @MainActor
    private func applyHeadPick(
        _ item: PhotosPickerItem?,
        slot: PairHeadPhotos.Slot,
        picker: Binding<PhotosPickerItem?>
    ) async {
        defer { picker.wrappedValue = nil }
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = PairHeadPhotos.compressedHead(image) else { return }
        session.setHeadPhoto(slot: slot, data: jpeg)
    }

    private var inviteCard: some View {
        pairCard {
            cardTitle("Share one list", number: 2, icon: "link", tint: Color(red: 0.22, green: 0.78, blue: 0.48))
            Text("Invite your partner with a code. They install Save4Two, then enter the code.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await createInvite() }
            } label: {
                Label(
                    session.inviteCode == nil ? "Invite Partner" : "Show my code",
                    systemImage: "square.and.arrow.up"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(Palette.brandBlue(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy || !session.hasNames)
            .opacity(session.isBusy || !session.hasNames ? 0.55 : 1)

            if let code = session.inviteCode {
                Text(code)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                Button("Send \(session.partnerHeartLabel) the code") { showShare = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var joinCard: some View {
        pairCard {
            cardTitle("I have a code", number: 3, icon: "key.fill", tint: Color(red: 0.62, green: 0.38, blue: 0.98))
            Text("Enter the 6-digit code from your partner.")
                .font(.caption)
                .foregroundStyle(.secondary)
            pairField("6-digit code", text: $joinCode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
            Button {
                Task { await join() }
            } label: {
                Text("Join Partner")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Palette.brandBlue(colorScheme))
                    .background(softButtonFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy || !session.hasNames || joinCode.trimmingCharacters(in: .whitespaces).count != 6)
            .opacity(session.isBusy || !session.hasNames || joinCode.trimmingCharacters(in: .whitespaces).count != 6 ? 0.55 : 1)
        }
    }

    private var connectedCard: some View {
        pairCard {
            Label("Phones are paired", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.brandBlue(colorScheme))
            Text("This phone is \(session.myHeartLabel). Hearts and new items sync to \(session.partnerHeartLabel).")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let code = session.inviteCode, session.role == .chris {
                Text("Invite code: \(code)")
                    .font(.subheadline.weight(.semibold))
                Button("Send the code again") { showShare = true }
                    .font(.subheadline.weight(.semibold))
                Button("New invite code") {
                    Task { await createInvite() }
                }
                .font(.subheadline)
                .disabled(session.isBusy || !session.hasNames)
            }
            Button {
                session.unpair()
            } label: {
                Label(
                    session.hasMultiplePairs
                        ? "Unpair \(session.partnerHeartLabel)"
                        : "Unpair phones",
                    systemImage: "heart.slash.fill"
                )
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.red)
            .accessibilityLabel("Unpair \(session.partnerHeartLabel)")
        }
    }

    private var desktopLinkCard: some View {
        pairCard {
            cardTitle("Link desktop", icon: "desktopcomputer", tint: Palette.brandBlue(colorScheme))
            Text("Get a code for the S42 browser extension (Chrome or Safari). Sent links show under From desktop when you add an item.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let code = desktopInbox.linkCode {
                Text(code)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityLabel("Desktop link code \(code)")
                if let expires = desktopInbox.linkCodeExpiresAt {
                    Text("Expires \(expires, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            Button {
                guard let pairID = session.pairID else { return }
                let label = "\(session.myHeartLabel) & \(session.partnerHeartLabel)"
                Task {
                    await desktopInbox.startDesktopLink(pairID: pairID, pairLabel: label)
                }
            } label: {
                Text(desktopInbox.linkCode == nil ? "Create desktop code" : "New desktop code")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Palette.brandBlue(colorScheme))
                    .background(softButtonFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(desktopInbox.isLoading || session.pairID == nil)
            if !desktopInbox.lastError.isEmpty {
                Text(desktopInbox.lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var restoreCard: some View {
        pairCard {
            cardTitle("Restore from iCloud", icon: "clock.fill", tint: Color(red: 0.98, green: 0.72, blue: 0.20))
            Text("Lost the list after a new invite? Enter an older 6-digit code from Messages, then restore.")
                .font(.caption)
                .foregroundStyle(.secondary)
            pairField("Older 6-digit code", text: $restoreCode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
            Button {
                Task { await restore() }
            } label: {
                Label("Restore my list from iCloud", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Palette.brandBlue(colorScheme))
                    .background(softButtonFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)
        }
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.25))
            Text("OR")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.25))
        }
        .padding(.horizontal, 8)
    }

    private func pairCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.isDark(colorScheme) ? Color.white.opacity(0.16) : Color.clear, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(Palette.isDark(colorScheme) ? 0 : 0.06), radius: 12, y: 4)
    }

    private func cardTitle(_ title: String, number: Int? = nil, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint, in: Circle())
            Text(number.map { "\($0). \(title)" } ?? title)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func pairField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(.subheadline)
            .textInputAutocapitalization(.words)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }

    private var pillFill: Color {
        Palette.isDark(colorScheme) ? Color.white.opacity(0.12) : Color.white.opacity(0.92)
    }

    private var softButtonFill: Color {
        Palette.brandBlue(colorScheme).opacity(Palette.isDark(colorScheme) ? 0.22 : 0.12)
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

    private func createInvite() async {
        errorText = ""
        session.isBusy = true
        defer { session.isBusy = false }
        session.persistLocal()
        do {
            _ = try await CloudSync.shared.createInvite()
            await CloudSync.shared.sync(modelContext: modelContext, allowCreate: true)
            showShare = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func restore() async {
        errorText = ""
        session.isBusy = true
        defer { session.isBusy = false }
        await CloudSync.shared.restoreFromCloud(modelContext: modelContext, oldCode: restoreCode)
        if session.statusMessage.isEmpty == false, session.statusMessage.contains("no saved") {
            errorText = session.statusMessage
        }
    }

    private func join() async {
        errorText = ""
        session.isBusy = true
        defer { session.isBusy = false }
        session.persistLocal()
        do {
            try await CloudSync.shared.join(code: joinCode)
            await CloudSync.shared.sync(modelContext: modelContext, allowCreate: true)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct PairBrandMark: View {
    var body: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.20, green: 0.48, blue: 0.98))
                .offset(x: 4, y: 2)
            Image(systemName: "heart.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.22, green: 0.78, blue: 0.55))
                .offset(x: -4, y: -2)
        }
        .frame(width: 22, height: 18)
        .accessibilityHidden(true)
    }
}

private struct PairPhonesArt: View {
    private let bezel = Color(red: 0.12, green: 0.20, blue: 0.38)
    private let sparkle = Color(red: 0.45, green: 0.62, blue: 0.95)

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                phone(
                    screen: Color(red: 0.86, green: 0.92, blue: 1.0),
                    heart: Color(red: 0.27, green: 0.52, blue: 0.95)
                )
                .rotationEffect(.degrees(-8))
                phone(
                    screen: Color(red: 0.82, green: 0.94, blue: 0.88),
                    heart: Color(red: 0.40, green: 0.72, blue: 0.55)
                )
                .rotationEffect(.degrees(8))
            }
            .offset(y: 10)

            HStack(alignment: .bottom, spacing: 5) {
                bang.rotationEffect(.degrees(-22))
                bang
                bang.rotationEffect(.degrees(22))
            }
            .foregroundStyle(sparkle)
            .offset(y: -40)
        }
    }

    private var bang: some View {
        VStack(spacing: 2) {
            Capsule()
                .frame(width: 3.5, height: 12)
            Circle()
                .frame(width: 3.5, height: 3.5)
        }
    }

    private func phone(screen: Color, heart: Color) -> some View {
        let width: CGFloat = 46
        let height: CGFloat = 76
        return ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(bezel)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(screen)
                .padding(3.5)
            Capsule()
                .fill(bezel)
                .frame(width: 16, height: 3.5)
                .offset(y: -(height / 2) + 11)
            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(heart)
        }
        .frame(width: width, height: height)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
