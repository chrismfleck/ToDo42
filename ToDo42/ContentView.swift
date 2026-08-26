import SwiftUI
import SwiftData
import UIKit

private let brandBlue = Color(red: 0.14, green: 0.42, blue: 0.92)
private let mist = Color(red: 0.93, green: 0.96, blue: 1.0)

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]
    @Environment(\.scenePhase) private var scenePhase
    @State private var category: ItemCategory = .places
    @State private var showAdd = false
    @State private var swipingItemID: UUID?

    private var filtered: [TodoItem] {
        items.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [mist, .white], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 22) {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 8) {
                            Text("ToDo42")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(brandBlue)
                            Text("ToDo's for Two")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                        Button { showAdd = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(brandBlue)
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
                                        modelContext.delete(item)
                                    }
                                } content: {
                                    NavigationLink {
                                        ItemDetailView(item: item)
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
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
        .tint(brandBlue)
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
            let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let link = payload.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            modelContext.insert(
                TodoItem(
                    title: title,
                    category: ItemCategory(rawValue: payload.category) ?? .places,
                    urlString: link.isEmpty ? nil : link,
                    imageData: imageData,
                    notes: payload.notes
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
    let item: TodoItem

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ItemPhotoView(item: item, cornerRadius: 14)
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if let url = item.urlString, !url.isEmpty {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(item.isDone ? 0.7 : 1)
    }
}

struct ItemDetailView: View {
    @Bindable var item: TodoItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ItemPhotoView(item: item, cornerRadius: 0, placeholderIconSize: 48)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipped()

                VStack(alignment: .leading, spacing: 16) {
                    Text(item.title)
                        .font(.title.bold())
                        .padding(.top, 4)

                    HStack(spacing: 28) {
                        PartnerHeartButton(name: "Chris", isOn: $item.chrisHearted)
                        PartnerHeartButton(name: "Deena", isOn: $item.deenaHearted)
                        DoneCheckButton(isDone: $item.isDone, size: 34, name: "Done")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    if let s = item.urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
                       let url = URL(string: s), !s.isEmpty {
                        Link(destination: url) {
                            Label("Open link", systemImage: "link")
                                .font(.headline)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Add a note", text: $item.notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .padding(20)
            }
        }
        .background(mist.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(item.title)
    }
}

private let heartPink = Color(red: 0.92, green: 0.28, blue: 0.45)

struct DoneCheckButton: View {
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
                    .foregroundStyle(isDone ? brandBlue : Color.secondary.opacity(0.55))
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
        .tint(brandBlue)
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
                            mist
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
        .background(mist)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            mist
            Image(systemName: item.category.systemImage)
                .font(.system(size: placeholderIconSize))
                .foregroundStyle(brandBlue)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
}
