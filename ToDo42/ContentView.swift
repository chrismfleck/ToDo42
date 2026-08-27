import SwiftUI
import SwiftData
import UIKit
import PhotosUI

enum Palette {
    static func isDark(_ scheme: ColorScheme) -> Bool {
        scheme == .dark || UITraitCollection.current.userInterfaceStyle == .dark
    }

    static func brandBlue(_ scheme: ColorScheme) -> Color {
        isDark(scheme)
            ? Color(red: 0.45, green: 0.66, blue: 1.0)
            : Color(red: 0.14, green: 0.42, blue: 0.92)
    }

    static func canvas(_ scheme: ColorScheme) -> Color {
        isDark(scheme) ? .black : Color(red: 0.93, green: 0.96, blue: 1.0)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        isDark(scheme) ? .black : .white
    }

    static func uiCanvas(_ scheme: ColorScheme) -> UIColor {
        isDark(scheme) ? .black : UIColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1)
    }
}

private extension View {
    func appCard(cornerRadius: CGFloat, scheme: ColorScheme) -> some View {
        background(Palette.card(scheme), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.isDark(scheme) ? Color.white.opacity(0.16) : Color.clear, lineWidth: 1)
            }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var items: [TodoItem]
    @Environment(\.scenePhase) private var scenePhase
    @State private var category: ItemCategory = .places
    @State private var showAdd = false
    @State private var showPairing = false
    @ObservedObject private var pairSession = PairSession.shared
    @State private var swipingItemID: UUID?
    @State private var selectedItem: TodoItem?
    @State private var isListEditing = false
    @State private var reorderDrag: ReorderDrag?
    @State private var rowHeights: [UUID: CGFloat] = [:]

    private var filtered: [TodoItem] {
        items
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var pagerItems: [TodoItem] {
        var list = filtered
        if let selected = selectedItem, !list.contains(where: { $0.id == selected.id }) {
            list.insert(selected, at: 0)
        }
        return list
    }

    private var reorderRowStride: CGFloat {
        let heights = filtered.compactMap { rowHeights[$0.id] }
        let averageHeight = heights.isEmpty ? 104 : heights.reduce(0, +) / CGFloat(heights.count)
        return averageHeight + 14
    }

    var body: some View {
        ZStack {
            Palette.canvas(colorScheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    Image("TitleWordmark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 44)
                        .foregroundStyle(Palette.brandBlue(colorScheme))
                        .accessibilityLabel("ToDo 4 2")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                    HStack {
                        Button(isListEditing ? "Done" : "Edit") {
                            if isListEditing {
                                reorderDrag = nil
                                isListEditing = false
                            } else {
                                normalizeSortOrders()
                                isListEditing = true
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.brandBlue(colorScheme))
                        .accessibilityLabel(isListEditing ? "Done reordering" : "Reorder list")

                        Spacer()

                        Button { showPairing = true } label: {
                            Image(systemName: pairSession.isPaired ? "person.2.fill" : "person.2")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Palette.brandBlue(colorScheme))
                        }
                        .accessibilityLabel("Pair phones")

                        Button { showAdd = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Palette.brandBlue(colorScheme))
                        }
                        .accessibilityLabel("Add item")
                    }
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
                                swipingItemID: $swipingItemID,
                                isEnabled: !isListEditing
                            ) {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    if selectedItem?.id == item.id { selectedItem = nil }
                                    let id = item.id
                                    modelContext.delete(item)
                                    Task { await CloudSync.shared.deleteRemote(id) }
                                }
                            } content: {
                                Group {
                                    if isListEditing {
                                        ItemRowView(
                                            item: item,
                                            showsDragHandle: true,
                                            onHandleDragChanged: { translation in
                                                handleReorderChanged(item: item, translation: translation)
                                            },
                                            onHandleDragEnded: {
                                                handleReorderEnded(item: item)
                                            }
                                        )
                                    } else {
                                        Button {
                                            selectedItem = item
                                        } label: {
                                            ItemRowView(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .offset(y: reorderOffset(for: item))
                            .zIndex(reorderDrag?.id == item.id ? 1 : 0)
                            .scaleEffect(reorderDrag?.id == item.id ? 1.02 : 1)
                            .shadow(
                                color: reorderDrag?.id == item.id ? Color.black.opacity(0.18) : .clear,
                                radius: 12,
                                y: 6
                            )
                            .animation(
                                reorderDrag?.id == item.id
                                    ? nil
                                    : .interactiveSpring(response: 0.25, dampingFraction: 0.86),
                                value: reorderOffset(for: item)
                            )
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: RowHeightPreferenceKey.self,
                                        value: [item.id: geo.size.height]
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .onPreferenceChange(RowHeightPreferenceKey.self) { rowHeights = $0 }
                }
                .scrollDisabled(reorderDrag != nil)
            }
        }
        .background(WindowCanvas(color: Palette.uiCanvas(colorScheme)))
        .tint(Palette.brandBlue(colorScheme))
        .fullScreenCover(isPresented: Binding(
            get: { selectedItem != nil },
            set: { if !$0 { selectedItem = nil } }
        )) {
            ItemPagerView(items: pagerItems, selectedItem: $selectedItem)
                .presentationBackground(Palette.canvas(colorScheme))
        }
        .sheet(isPresented: $showAdd) {
            AddItemView(category: category)
        }
        .sheet(isPresented: $showPairing) {
            PairingView()
        }
        .onAppear {
            importSharedDrafts()
            seedIfNeeded()
            normalizeStoredText()
            Task { await CloudSync.shared.sync(modelContext: modelContext, items: items) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                importSharedDrafts()
                Task { await CloudSync.shared.sync(modelContext: modelContext, items: items) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todo42CloudPush)) { _ in
            Task { await CloudSync.shared.sync(modelContext: modelContext, items: items) }
        }
        .onChange(of: category) { _, _ in
            reorderDrag = nil
        }
    }

    private func normalizeSortOrders() {
        for cat in ItemCategory.allCases {
            let ordered = items
                .filter { $0.category == cat }
                .sorted { lhs, rhs in
                    if lhs.sortOrder == rhs.sortOrder {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.sortOrder < rhs.sortOrder
                }
            for (index, item) in ordered.enumerated() {
                item.sortOrder = index
            }
        }
    }

    private func nextSortOrder(for category: ItemCategory) -> Int {
        (items.filter { $0.category == category }.map(\.sortOrder).min() ?? 0) - 1
    }

    private func normalizeStoredText() {
        for item in items {
            let title = SharedText.normalized(item.title)
            if item.title != title { item.title = title }
            let notes = SharedText.normalized(item.notes)
            if item.notes != notes { item.notes = notes }
        }
    }

    private func reorderOffset(for item: TodoItem) -> CGFloat {
        guard let drag = reorderDrag,
              let from = filtered.firstIndex(where: { $0.id == drag.id }),
              let index = filtered.firstIndex(where: { $0.id == item.id })
        else { return 0 }

        if item.id == drag.id { return drag.translation }

        let to = targetIndex(from: from, translation: drag.translation)
        if from < to, index > from, index <= to { return -reorderRowStride }
        if from > to, index < from, index >= to { return reorderRowStride }
        return 0
    }

    private func targetIndex(from: Int, translation: CGFloat) -> Int {
        let last = max(filtered.count - 1, 0)
        return min(max(from + Int((translation / reorderRowStride).rounded()), 0), last)
    }

    private func handleReorderChanged(item: TodoItem, translation: CGFloat) {
        if reorderDrag == nil {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        reorderDrag = ReorderDrag(id: item.id, translation: translation)
    }

    private func handleReorderEnded(item: TodoItem) {
        guard let drag = reorderDrag, drag.id == item.id,
              let from = filtered.firstIndex(where: { $0.id == item.id })
        else {
            reorderDrag = nil
            return
        }

        let to = targetIndex(from: from, translation: drag.translation)
        var ordered = filtered
        if from != to {
            ordered.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if from != to {
                for (index, row) in ordered.enumerated() {
                    row.sortOrder = index
                }
            }
            reorderDrag = nil
        }
    }

    private func seedIfNeeded() {
        let key = "todo42.seeded.v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        if items.isEmpty {
            for cat in ItemCategory.allCases {
                for (index, seed) in SampleData.seeds.filter({ $0.category == cat }).enumerated() {
                    modelContext.insert(SampleData.makeItem(seed, sortOrder: index))
                }
            }
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
        var nextOrders: [ItemCategory: Int] = [:]
        for (payload, imageData) in ShareInbox.consumeDrafts() {
            let title = SharedText.normalized(payload.title)
            guard !title.isEmpty else { continue }
            let link = payload.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            let category = ItemCategory(rawValue: payload.category) ?? .places
            let sortOrder = nextOrders[category] ?? nextSortOrder(for: category)
            nextOrders[category] = sortOrder - 1
            modelContext.insert(
                TodoItem(
                    title: title,
                    category: category,
                    urlString: link.isEmpty ? nil : link,
                    imageData: imageData,
                    notes: SharedText.normalized(payload.notes),
                    sortOrder: sortOrder
                )
            )
        }
    }
}

private struct ReorderDrag {
    var id: UUID
    var translation: CGFloat
}

private struct RowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct OptionalSwipeGesture<G: Gesture>: ViewModifier {
    var isEnabled: Bool
    var gesture: G

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(gesture)
        } else {
            content
        }
    }
}

private let deleteRevealWidth: CGFloat = 88

struct SwipeToDeleteRow<Content: View>: View {
    let itemID: UUID
    @Binding var swipingItemID: UUID?
    var isEnabled: Bool = true
    var onDelete: () -> Void
    @ViewBuilder var content: Content
    @State private var offset: CGFloat = 0
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        content
            .offset(x: isEnabled ? offset : 0)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { rowWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, width in
                            rowWidth = width
                        }
                }
            }
            .modifier(OptionalSwipeGesture(isEnabled: isEnabled, gesture: swipeGesture))
            .onChange(of: isEnabled) { _, enabled in
                guard !enabled, offset != 0 else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    offset = 0
                }
            }
            .onChange(of: swipingItemID) { _, newValue in
                if newValue != itemID, offset != 0 {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        offset = 0
                    }
                }
            }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard isEnabled else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                if swipingItemID != itemID {
                    swipingItemID = itemID
                }
                offset = min(0, horizontal)
            }
            .onEnded { value in
                guard isEnabled else {
                    offset = 0
                    return
                }
                let shouldDelete = value.translation.width < -120
                    || value.predictedEndTranslation.width < -200
                if shouldDelete {
                    withAnimation(.easeIn(duration: 0.18)) {
                        offset = -(rowWidth > 0 ? rowWidth : 400)
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
    }
}

struct ItemRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: TodoItem
    var showsDragHandle: Bool = false
    var onHandleDragChanged: ((CGFloat) -> Void)?
    var onHandleDragEnded: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ItemPhotoView(item: item, cornerRadius: 14)
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                LockedText(
                    text: item.title,
                    font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    color: .label,
                    lines: 2
                )
                if !item.notes.isEmpty {
                    LockedText(
                        text: item.notes,
                        font: UIFont.systemFont(ofSize: 12, weight: .regular),
                        color: .secondaryLabel,
                        lines: 1
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(.large)

            if showsDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                onHandleDragChanged?(value.translation.height)
                            }
                            .onEnded { _ in
                                onHandleDragEnded?()
                            }
                    )
                    .accessibilityLabel("Reorder")
            }
        }
        .padding(14)
        .appCard(cornerRadius: 18, scheme: colorScheme)
        .opacity(item.isDone ? 0.7 : 1)
    }
}

private struct LockedText: UIViewRepresentable {
    var text: String
    var font: UIFont
    var color: UIColor
    var lines: Int

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = lines
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = SharedText.normalized(text)
        label.font = font
        label.textColor = color
        label.numberOfLines = lines
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.preferredMaxLayoutWidth
        guard width.isFinite, width > 0 else {
            return uiView.intrinsicContentSize
        }
        uiView.preferredMaxLayoutWidth = width
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }
}

struct ItemPagerView: View {
    let items: [TodoItem]
    @Binding var selectedItem: TodoItem?
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedID: UUID
    @State private var isEditing = false

    init(items: [TodoItem], selectedItem: Binding<TodoItem?>) {
        self.items = items
        self._selectedItem = selectedItem
        _selectedID = State(initialValue: selectedItem.wrappedValue?.id ?? items.first?.id ?? UUID())
    }

    var body: some View {
        TabView(selection: $selectedID) {
            ForEach(items, id: \.id) { item in
                ItemDetailView(item: item, onEditingChange: { editing in
                    if item.id == selectedID {
                        isEditing = editing
                    }
                })
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .scrollDisabled(isEditing)
        .background(Palette.canvas(colorScheme).ignoresSafeArea())
        .onChange(of: selectedID) { _, newID in
            if let match = items.first(where: { $0.id == newID }) {
                selectedItem = match
            }
            isEditing = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .accessibilityHint(items.count > 1 ? "Swipe left or right to see other items" : "")
    }
}

struct ItemDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: TodoItem
    var onEditingChange: ((Bool) -> Void)? = nil
    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var draftLink = ""
    @State private var draftNotes = ""
    @State private var draftCategory: ItemCategory = .places
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if isEditing { commitEdits() }
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.brandBlue(colorScheme))
                        .frame(width: 32, height: 32, alignment: .leading)
                }
                .accessibilityLabel("Back")

                Spacer()

                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        commitEdits()
                    } else {
                        beginEditing()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.brandBlue(colorScheme))
                .disabled(isEditing && draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(isEditing ? "Done editing" : "Edit item")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Palette.canvas(colorScheme))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    photoSection

                    VStack(alignment: .leading, spacing: 16) {
                        if isEditing {
                            labeledField("Title") {
                                TextField("Title", text: $draftTitle)
                                    .font(.title.bold())
                                    .padding(12)
                                    .appCard(cornerRadius: 12, scheme: colorScheme)
                            }
                        } else {
                            Text(verbatim: SharedText.normalized(item.title))
                                .font(.title.bold())
                                .padding(.top, 4)
                        }

                        HStack(spacing: 28) {
                            PartnerHeartButton(name: "Chris", isOn: $item.chrisHearted)
                            PartnerHeartButton(name: "Deena", isOn: $item.deenaHearted)
                            DoneCheckButton(isDone: $item.isDone, size: 34, name: "Done")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .onChange(of: item.chrisHearted) { _, _ in
                            PairSession.shared.noteLocalEdit(item, kind: "heart")
                        }
                        .onChange(of: item.deenaHearted) { _, _ in
                            PairSession.shared.noteLocalEdit(item, kind: "heart")
                        }
                        .onChange(of: item.isDone) { _, _ in
                            PairSession.shared.noteLocalEdit(item, kind: "edit")
                        }

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

                            if !item.notes.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Notes")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(verbatim: SharedText.normalized(item.notes))
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(false)
        }
        .background(Palette.canvas(colorScheme).ignoresSafeArea())
        .onChange(of: photoItem) { _, newItem in
            Task { await applyPickedPhoto(newItem) }
        }
        .onDisappear {
            if isEditing { commitEdits() }
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        if item.hasPhoto {
            ItemPhotoView(item: item, cornerRadius: 0, placeholderIconSize: 48)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
        } else {
            PhotosPicker(selection: $photoItem, matching: .images) {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 36, weight: .medium))
                    Text("Upload photo")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Palette.brandBlue(colorScheme))
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .background(Palette.canvas(colorScheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Upload photo")
        }
    }

    private func applyPickedPhoto(_ picked: PhotosPickerItem?) async {
        guard let picked else { return }
        guard let data = try? await picked.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = PhotoJPEG.compressed(image) else { return }
        item.imageData = jpeg
        item.imageAssetName = nil
        item.imageURLString = nil
        PairSession.shared.noteLocalEdit(item, kind: "edit")
        PairSession.shared.noteLocalEdit(item, kind: "edit")
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
        onEditingChange?(true)
    }

    private func commitEdits() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            item.title = SharedText.normalized(trimmedTitle)
        }
        let trimmedLink = draftLink.trimmingCharacters(in: .whitespacesAndNewlines)
        item.urlString = trimmedLink.isEmpty ? nil : trimmedLink
        item.notes = SharedText.normalized(draftNotes)
        item.category = draftCategory
        PairSession.shared.noteLocalEdit(item, kind: "edit")
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
        onEditingChange?(false)
    }
}

private enum PhotoJPEG {
    static func compressed(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.82) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scaled: UIImage
        if longest > maxSide {
            let scale = maxSide / longest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        } else {
            scaled = image
        }
        return scaled.jpegData(compressionQuality: quality)
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
    @Query private var items: [TodoItem]
    var category: ItemCategory

    @State private var title = ""
    @State private var urlString = ""
    @State private var notes = ""
    @State private var selectedCategory: ItemCategory = .places
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        if let photoData, let uiImage = UIImage(data: photoData) {
                            HStack(spacing: 12) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Photo added")
                                        .foregroundStyle(.primary)
                                    Text("Tap to change")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        } else {
                            Label("Add photo", systemImage: "photo.badge.plus")
                        }
                    }
                    .accessibilityLabel(photoData == nil ? "Add photo" : "Change photo")

                    if photoData != nil {
                        Button("Remove photo", role: .destructive) {
                            photoItem = nil
                            photoData = nil
                        }
                    }

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
            .onChange(of: photoItem) { _, newItem in
                Task { await loadPickedPhoto(newItem) }
            }
        }
        .tint(Palette.brandBlue(colorScheme))
    }

    private func loadPickedPhoto(_ picked: PhotosPickerItem?) async {
        guard let picked else { return }
        guard let data = try? await picked.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = PhotoJPEG.compressed(image) else { return }
        photoData = jpeg
    }

    private func save() {
        let trimmedTitle = SharedText.normalized(title)
        let trimmedLink = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = SharedText.normalized(notes)
        let nextSortOrder = (items.filter { $0.category == selectedCategory }.map(\.sortOrder).min() ?? 0) - 1
        let item = TodoItem(
            title: trimmedTitle,
            category: selectedCategory,
            urlString: trimmedLink.isEmpty ? nil : trimmedLink,
            imageData: photoData,
            notes: trimmedNotes,
            sortOrder: nextSortOrder
        )
        modelContext.insert(item)
        PairSession.shared.noteLocalEdit(item, kind: "add")
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

private struct WindowCanvas: UIViewRepresentable {
    var color: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            uiView.window?.backgroundColor = color
            uiView.window?.rootViewController?.view.backgroundColor = color
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
