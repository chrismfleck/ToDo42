import SwiftUI
import SwiftData
import UIKit

enum Palette {
    static func brandBlue(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.45, green: 0.66, blue: 1.0)
            : Color(red: 0.14, green: 0.42, blue: 0.92)
    }

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : Color(red: 0.93, green: 0.96, blue: 1.0)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }
}

private extension View {
    func appCard(cornerRadius: CGFloat, scheme: ColorScheme) -> some View {
        background(Palette.card(scheme), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(scheme == .dark ? Color.white.opacity(0.16) : Color.clear, lineWidth: 1)
            }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]
    @Environment(\.scenePhase) private var scenePhase
    @State private var category: ItemCategory = .places
    @State private var showAdd = false
    @State private var swipingItemID: UUID?
    @State private var selectedItemID: UUID?

    private var filtered: [TodoItem] {
        items.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.canvas(colorScheme)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 22) {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 8) {
                            Text("ToDo42")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.brandBlue(colorScheme))
                            Text("ToDo's for Two")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                        Button { showAdd = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Palette.brandBlue(colorScheme))
                        }
                        .accessibilityLabel("Add item")
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)

                    Picker("Category", selection: $category) {
                        ForEach(ItemCategory.allCases) { cat in
                            Text(cat.title).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)

                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(filtered, id: \.id) { item in
                                SwipeToDeleteRow(
                                    itemID: item.id,
                                    swipingItemID: $swipingItemID
                                ) {
                                    withAnimation(.easeIn(duration: 0.2)) {
                                        if selectedItemID == item.id { selectedItemID = nil }
                                        modelContext.delete(item)
                                    }
                                } content: {
                                    Button {
                                        selectedItemID = item.id
                                    } label: {
                                        ItemRowView(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Palette.canvas(colorScheme))
                }
            }
            .background(HideNavigationBar(hidden: true))
            .containerBackground(Palette.canvas(colorScheme), for: .navigation)
            .navigationDestination(item: $selectedItemID) { id in
                if let item = items.first(where: { $0.id == id }) {
                    ItemDetailView(item: item)
                }
            }
            .sheet(isPresented: $showAdd) {
                AddItemView(category: category)
            }
            .onAppear {
                importSharedDrafts()
                seedIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { importSharedDrafts() }
            }
        }
        .tint(Palette.brandBlue(colorScheme))
        .containerBackground(Palette.canvas(colorScheme), for: .navigation)
    }

    private func seedIfNeeded() {
        let key = "todo42.seeded.v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        if items.isEmpty {
            SampleData.seeds.forEach { modelContext.insert(SampleData.makeItem($0)) }
        } else {
            for item in items {
                guard let sample = SampleData.matching(title: item.title) else { continue }
                if item.imageAssetName == nil {
                    item.imageAssetName = sample.imageAssetName
                }
                if item.urlString == nil {
                    item.urlString = sample.urlString
                }
                if item.notes.isEmpty {
                    item.notes = sample.notes
                }
            }
        }

        UserDefaults.standard.set(true, forKey: key)
    }

    private func importSharedDrafts() {
        for (payload, imageData) in ShareInbox.consumeDrafts() {
            var title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let link = payload.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            var notes = payload.notes
            if SharedCopy.isInstagramOrAirbnb(urlString: link, title: title) {
                title = SharedCopy.clamped(title)
                notes = SharedCopy.clamped(notes)
            }
            modelContext.insert(
                TodoItem(
                    title: title,
                    category: ItemCategory(rawValue: payload.category) ?? .places,
                    urlString: link.isEmpty ? nil : link,
                    imageData: imageData,
                    notes: notes
                )
            )
        }
    }
}

private let deleteRevealWidth: CGFloat = 88

struct SwipeToDeleteRow<Content: View>: View {
    let itemID: UUID
    @Binding var swipingItemID: UUID?
    var onDelete: () -> Void
    @ViewBuilder var content: Content
    @State private var offset: CGFloat = 0

    var body: some View {
        content
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > abs(vertical) else { return }
                        if swipingItemID != itemID {
                            swipingItemID = itemID
                        }
                        offset = min(0, horizontal)
                    }
                    .onEnded { value in
                        let shouldDelete = value.translation.width < -120
                            || value.predictedEndTranslation.width < -200
                        if shouldDelete {
                            withAnimation(.easeIn(duration: 0.18)) {
                                offset = -UIScreen.main.bounds.width
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                onDelete()
                                if swipingItemID == itemID { swipingItemID = nil }
                            }
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                offset = 0
                            }
                            if swipingItemID == itemID { swipingItemID = nil }
                        }
                    }
            )
            .onChange(of: swipingItemID) { _, newValue in
                if newValue != itemID, offset != 0 {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        offset = 0
                    }
                }
            }
    }
}

struct ItemRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: TodoItem

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ItemPhotoView(item: item, cornerRadius: 14)
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle)
                    .font(item.usesCompactSharedText ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(item.usesCompactSharedText ? 4 : 2)
                    .foregroundStyle(.primary)
                if let url = item.urlString, !url.isEmpty {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !item.displayNotes.isEmpty {
                    Text(item.displayNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .appCard(cornerRadius: 18, scheme: colorScheme)
        .opacity(item.isDone ? 0.7 : 1)
    }
}

struct ItemDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var item: TodoItem
    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var draftLink = ""
    @State private var draftNotes = ""
    @State private var draftCategory: ItemCategory = .places

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ItemPhotoView(item: item, cornerRadius: 0, placeholderIconSize: 48)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipped()

                VStack(alignment: .leading, spacing: 16) {
                        if isEditing {
                            labeledField("Title") {
                                TextField("Title", text: $draftTitle)
                                    .font(item.usesCompactSharedText ? .body : .title.bold())
                                    .padding(12)
                                    .appCard(cornerRadius: 12, scheme: colorScheme)
                            }
                        } else {
                            Text(item.displayTitle)
                                .font(item.usesCompactSharedText ? .body : .title.bold())
                                .padding(.top, 4)
                        }

                    HStack(spacing: 28) {
                        PartnerHeartButton(name: "Chris", isOn: $item.chrisHearted)
                        PartnerHeartButton(name: "Deena", isOn: $item.deenaHearted)
                        DoneCheckButton(isDone: $item.isDone, size: 34, name: "Done")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    if isEditing {
                        labeledField("Link") {
                            TextField("https://", text: $draftLink)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .padding(12)
                                .appCard(cornerRadius: 12, scheme: colorScheme)
                        }

                        labeledField("Notes") {
                            TextField("Add a note", text: $draftNotes, axis: .vertical)
                                .font(.body)
                                .lineLimit(3...8)
                                .padding(12)
                                .appCard(cornerRadius: 12, scheme: colorScheme)
                        }

                        labeledField("Category") {
                            Picker("Category", selection: $draftCategory) {
                                ForEach(ItemCategory.allCases) { cat in
                                    Text(cat.title).tag(cat)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    } else {
                        if let s = item.urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
                           let url = URL(string: s), !s.isEmpty {
                            Link(destination: url) {
                                Label("Open link", systemImage: "link")
                                    .font(.headline)
                            }
                        }

                        if !item.displayNotes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notes")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(item.displayNotes)
                                    .font(.body)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.canvas(colorScheme))
        .safeAreaInset(edge: .top, alignment: .leading, spacing: 0) {
            Button(isEditing ? "Done" : "Edit") {
                if isEditing {
                    commitEdits()
                } else {
                    beginEditing()
                }
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(Palette.brandBlue(colorScheme))
            .disabled(isEditing && draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(isEditing ? "Done editing" : "Edit item")
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.canvas(colorScheme))
        }
        .containerBackground(Palette.canvas(colorScheme), for: .navigation)
        .toolbarBackground(Palette.canvas(colorScheme), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(item.usesCompactSharedText ? "Details" : item.displayTitle)
        .background(HideNavigationBar(hidden: false))
        .onDisappear {
            if isEditing { commitEdits() }
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func beginEditing() {
        draftTitle = item.title
        draftLink = item.urlString ?? ""
        draftNotes = item.notes
        draftCategory = item.category
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
    }

    private func commitEdits() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = draftLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.urlString = trimmedLink.isEmpty ? nil : trimmedLink
        let compact = SharedCopy.isInstagramOrAirbnb(urlString: item.urlString ?? "", title: trimmedTitle)
        if !trimmedTitle.isEmpty {
            item.title = compact ? SharedCopy.clamped(trimmedTitle) : trimmedTitle
        }
        item.notes = compact ? SharedCopy.clamped(trimmedNotes) : trimmedNotes
        item.category = draftCategory
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
    }
}

private let heartPink = Color(red: 0.92, green: 0.28, blue: 0.45)

struct DoneCheckButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isDone: Bool
    var size: CGFloat = 34
    var name: String? = nil

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.28)) {
                isDone.toggle()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(isDone ? Palette.brandBlue(colorScheme) : Color.secondary.opacity(0.55))
                    .scaleEffect(isDone ? 1.08 : 1)
                if let name {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: name == nil ? size + 8 : 72)
            .padding(.vertical, name == nil ? 4 : 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}

struct PartnerHeartButton: View {
    let name: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.28)) {
                isOn.toggle()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: isOn ? "heart.fill" : "heart")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(isOn ? heartPink : Color.secondary.opacity(0.55))
                    .scaleEffect(isOn ? 1.08 : 1)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 72)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) heart")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct AddItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var category: ItemCategory

    @State private var title = ""
    @State private var urlString = ""
    @State private var notes = ""
    @State private var selectedCategory: ItemCategory = .places

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Link", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ItemCategory.allCases) { cat in
                            Text(cat.title).tag(cat)
                        }
                    }
                }
            }
            .navigationTitle("Add item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { selectedCategory = category }
        }
        .tint(Palette.brandBlue(colorScheme))
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(
            TodoItem(
                title: trimmedTitle,
                category: selectedCategory,
                urlString: trimmedLink.isEmpty ? nil : trimmedLink,
                notes: trimmedNotes
            )
        )
        dismiss()
    }
}

struct ItemPhotoView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: TodoItem
    var cornerRadius: CGFloat = 12
    var placeholderIconSize: CGFloat = 22

    var body: some View {
        Group {
            if let data = item.imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let name = item.imageAssetName, !name.isEmpty {
                Image(name)
                    .resizable()
                    .scaledToFill()
            } else if let s = item.imageURLString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            Palette.canvas(colorScheme)
                            ProgressView()
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
        .clipped()
        .background(Palette.canvas(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Palette.canvas(colorScheme)
            Image(systemName: item.category.systemImage)
                .font(.system(size: placeholderIconSize))
                .foregroundStyle(Palette.brandBlue(colorScheme))
        }
    }
}

private struct HideNavigationBar: UIViewControllerRepresentable {
    var hidden: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller(hidden: hidden)
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.hidden = hidden
        uiViewController.apply()
    }

    final class Controller: UIViewController {
        var hidden: Bool

        init(hidden: Bool) {
            self.hidden = hidden
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if hidden {
                navigationController?.setNavigationBarHidden(false, animated: animated)
            }
        }

        func apply() {
            navigationController?.setNavigationBarHidden(hidden, animated: false)
        }
    }
}

#Preview("Light") {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
}

#Preview("Dark") {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
        .preferredColorScheme(.dark)
}
