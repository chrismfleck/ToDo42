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

extension View {
    func appCard(cornerRadius: CGFloat, scheme: ColorScheme) -> some View {
        background(Palette.card(scheme), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.isDark(scheme) ? Color.white.opacity(0.16) : Color.clear, lineWidth: 1)
            }
    }
}

private let heartPink = Color(red: 0.92, green: 0.28, blue: 0.45)

struct PairHeartPlusIcon: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack(alignment: .top) {
            Image(systemName: "heart.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.red)
            Image(systemName: "plus")
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(.white)
                .offset(y: size * 0.18)
        }
        .frame(width: size + 6, height: size + 2)
        .accessibilityHidden(true)
    }
}

struct PairHeadButton: View {
    let label: String
    var tint: Color
    var isActive: Bool = true
    var size: CGFloat = 30
    var imageData: Data? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PairHeadAvatar(label: label, tint: tint, isActive: isActive, size: size, imageData: imageData)
        }
        .buttonStyle(.plain)
    }
}

struct PairHeadAvatar: View {
    let label: String
    var tint: Color
    var isActive: Bool = true
    var size: CGFloat = 30
    var imageData: Data? = nil

    private var initials: String {
        let parts = label
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    private var fontSize: CGFloat {
        max(9, size * 0.36)
    }

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tint.opacity(isActive ? 1 : 0.45))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.85), lineWidth: isActive && size >= 28 ? 2 : 1)
        }
        .opacity(isActive ? 1 : 0.55)
    }
}

private struct CategoryTabStrip: View {
    var categories: [ItemCategory]
    var isSelected: (ItemCategory) -> Bool
    var onSelect: (ItemCategory) -> Void
    @Environment(CategoryNames.self) private var categoryNames
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(categories) { cat in
                let selected = isSelected(cat)
                Button {
                    onSelect(cat)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: cat.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(cat.iconColor)
                        Text(categoryNames.title(for: cat))
                            .font(.caption2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(Palette.brandBlue(colorScheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.card(colorScheme))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selected
                                    ? Palette.brandBlue(colorScheme)
                                    : (Palette.isDark(colorScheme) ? Color.white.opacity(0.16) : Color.black.opacity(0.06)),
                                lineWidth: selected ? 3 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(categoryNames.title(for: cat))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

struct CategoryPickerGrid: View {
    @Binding var selection: Set<ItemCategory>

    var body: some View {
        VStack(spacing: 8) {
            CategoryTabStrip(
                categories: ItemCategory.primaryPage,
                isSelected: { selection.contains($0) },
                onSelect: { toggle($0) }
            )
            CategoryTabStrip(
                categories: ItemCategory.extraPage,
                isSelected: { selection.contains($0) },
                onSelect: { toggle($0) }
            )
        }
    }

    private func toggle(_ cat: ItemCategory) {
        if selection.contains(cat) {
            guard selection.count > 1 else { return }
            selection.remove(cat)
        } else {
            selection.insert(cat)
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var items: [TodoItem]
    @Environment(\.scenePhase) private var scenePhase
    @State private var category: ItemCategory = .places
    @State private var categoryPage = 0
    @State private var pageSelection: [Int: ItemCategory] = [0: .places, 1: .trip]
    @State private var showAdd = false
    @State private var showPairing = false
    @State private var showHelp = false
    @Environment(PairSession.self) private var pairSession
    @State private var swipingItemID: UUID?
    @State private var selectedItem: TodoItem?
    @State private var isListEditing = !UserDefaults.standard.bool(forKey: Self.hasLeftListEditKey)
    @State private var reorderDrag: ReorderDrag?
    @State private var rowHeights: [UUID: CGFloat] = [:]

    private static let hasLeftListEditKey = "todo42.hasLeftListEditMode"

    private var pairScopedItems: [TodoItem] {
        let active = pairSession.pairID
        if let active, !active.isEmpty {
            return items.filter { $0.pairID == active || $0.pairID.isEmpty }
        }
        return items
    }

    private var filtered: [TodoItem] {
        pairScopedItems
            .filter { $0.belongs(to: category) }
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
                HStack(spacing: 0) {
                    Button {
                        toggleListEditing()
                    } label: {
                        Image(systemName: isListEditing ? "checkmark" : "pencil")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Palette.brandBlue(colorScheme))
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(isListEditing ? "Done editing" : "Edit list")

                    if isListEditing {
                        Button { showHelp = true } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Palette.brandBlue(colorScheme))
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Help")
                    }

                    Spacer(minLength: 10)

                    if pairSession.isPaired, !isListEditing {
                        PairHeadButton(
                            label: pairSession.myHeartLabel,
                            tint: Color(red: 0.20, green: 0.48, blue: 0.98),
                            isActive: true,
                            size: 39,
                            imageData: pairSession.headImageData(slot: .me)
                        ) {
                            if pairSession.hasMultiplePairs {
                                pairSession.switchToNextPair()
                                Task { await refreshFromCloud() }
                            } else {
                                showPairing = true
                            }
                        }
                        .accessibilityLabel(
                            pairSession.hasMultiplePairs
                                ? "Switch list. You are \(pairSession.myHeartLabel)"
                                : "You, \(pairSession.myHeartLabel)"
                        )

                        Spacer(minLength: 8)
                    }

                    Image("TitleWordmark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 28)
                        .foregroundStyle(Palette.brandBlue(colorScheme))
                        .accessibilityLabel("Save 4 Two")
                        .layoutPriority(1)

                    if pairSession.isPaired, !isListEditing {
                        Spacer(minLength: 8)

                        PairHeadButton(
                            label: pairSession.partnerHeartLabel,
                            tint: Color(red: 0.22, green: 0.78, blue: 0.55),
                            isActive: true,
                            size: 39,
                            imageData: pairSession.headImageData(slot: .partner)
                        ) {
                            if pairSession.hasMultiplePairs {
                                pairSession.switchToNextPair()
                                Task { await refreshFromCloud() }
                            } else {
                                showPairing = true
                            }
                        }
                        .accessibilityLabel(
                            pairSession.hasMultiplePairs
                                ? "Switch list. Current partner \(pairSession.partnerHeartLabel)"
                                : "Partner \(pairSession.partnerHeartLabel)"
                        )
                    }

                    Spacer(minLength: 10)

                    if isListEditing {
                        Button { showPairing = true } label: {
                            PairHeartPlusIcon(size: 22)
                        }
                        .accessibilityLabel("Pair phones")
                    }

                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Palette.brandBlue(colorScheme))
                    }
                    .accessibilityLabel("Add item")
                }
                .padding(.top, 10)
                .padding(.horizontal, 24)

                TabView(selection: $categoryPage) {
                    categoryPageView(ItemCategory.primaryPage, page: 0)
                        .tag(0)
                    categoryPageView(ItemCategory.extraPage, page: 1)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: categoryPage) { _, page in
                    category = pageSelection[page] ?? (page == 0 ? .places : .trip)
                    reorderDrag = nil
                }
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
                .environment(CategoryNames.shared)
                .environment(HomeBase.shared)
        }
        .sheet(isPresented: $showAdd) {
            AddItemView(category: category)
                .environment(CategoryNames.shared)
        }
        .sheet(isPresented: $showPairing) {
            PairingView()
                .environment(PairSession.shared)
                .environment(CategoryNames.shared)
                .environment(HomeBase.shared)
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
                .environment(CategoryNames.shared)
                .environment(HomeBase.shared)
        }
        .onAppear {
            ItemStore.migrateUnscopedItems(in: modelContext, to: pairSession.pairID)
            pairSession.persistLocal()
            importSharedDrafts()
            seedIfNeeded()
            repairSampleLinks()
            normalizeStoredText()
            Task { await refreshFromCloud() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                importSharedDrafts()
                Task { await refreshFromCloud() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todo42CloudPush)) { _ in
            Task { await refreshFromCloud() }
        }
        .onChange(of: category) { _, _ in
            reorderDrag = nil
        }
    }

    private func selectCategory(_ cat: ItemCategory) {
        category = cat
        categoryPage = cat.pageIndex
        pageSelection[cat.pageIndex] = cat
        reorderDrag = nil
    }

    private func items(in cat: ItemCategory) -> [TodoItem] {
        pairScopedItems
            .filter { $0.belongs(to: cat) }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    @ViewBuilder
    private func categoryPageView(_ categories: [ItemCategory], page: Int) -> some View {
        let selected = Binding(
            get: { pageSelection[page] ?? categories[0] },
            set: { selectCategory($0) }
        )
        VStack(alignment: .leading, spacing: 14) {
            CategoryTabStrip(
                categories: categories,
                isSelected: { $0 == selected.wrappedValue },
                onSelect: { selected.wrappedValue = $0 }
            )
                .padding(.horizontal, 24)
            itemList(for: selected.wrappedValue)
        }
    }

    private func itemList(for cat: ItemCategory) -> some View {
        let rows = items(in: cat)
        return ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(rows, id: \.persistentModelID) { item in
                    SwipeToDeleteRow(
                        itemID: item.id,
                        swipingItemID: $swipingItemID,
                        isEnabled: false
                    ) {
                        deleteItem(item)
                    } content: {
                        Group {
                            if isListEditing {
                                ItemRowView(
                                    item: item,
                                    showsDragHandle: true,
                                    onDelete: { deleteItem(item) },
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

    private func toggleListEditing() {
        if isListEditing {
            reorderDrag = nil
            isListEditing = false
            UserDefaults.standard.set(true, forKey: Self.hasLeftListEditKey)
        } else {
            normalizeSortOrders()
            isListEditing = true
        }
    }

    private func deleteItem(_ item: TodoItem) {
        withAnimation(.easeIn(duration: 0.2)) {
            if selectedItem?.id == item.id { selectedItem = nil }
            let id = item.id
            modelContext.delete(item)
            Task { await CloudSync.shared.deleteRemote(id) }
        }
    }

    private func refreshFromCloud() async {
        await CloudSync.shared.sync(modelContext: modelContext)
        seedIfNeeded()
        repairSampleLinks()
        if let cat = PairSession.shared.takeRevealCategory() {
            selectCategory(cat)
        }
    }

    private func normalizeSortOrders() {
        for cat in ItemCategory.allCases {
            let ordered = items
                .filter { $0.belongs(to: cat) }
                .sorted { lhs, rhs in
                    if lhs.sortOrder == rhs.sortOrder {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.sortOrder < rhs.sortOrder
                }
            var seen = Set<Int>()
            let hasClash = ordered.contains { !seen.insert($0.sortOrder).inserted }
            guard hasClash else { continue }
            for (index, item) in ordered.enumerated() {
                item.sortOrder = ListReorder.rebalanced(ordered.count)[index]
            }
        }
    }

    private func nextSortOrder(for category: ItemCategory) -> Int {
        (pairScopedItems.filter { $0.belongs(to: category) }.map(\.sortOrder).min() ?? 0) - 1
    }

    private func normalizeStoredText() {
        for item in items {
            var title = item.title
            var notes = item.notes
            let link = item.urlString ?? ""
            if InstagramShareText.isInstagramURL(link) || InstagramShareText.needsCleanup(title: title, notes: notes) {
                let split = InstagramShareText.refine(title: title, notes: notes)
                if !split.title.isEmpty {
                    title = split.title
                    notes = split.notes.isEmpty ? notes : split.notes
                }
            } else if FacebookShareText.isFacebookURL(link) || title.lowercased().contains("on facebook") {
                let split = FacebookShareText.refine(title: title, notes: notes)
                if !split.title.isEmpty {
                    title = split.title
                    notes = split.notes.isEmpty ? notes : split.notes
                }
            }
            let cut = SharedText.cutTitle(title, notes: notes)
            let nextTitle = SharedText.normalized(cut.title)
            let nextNotes = SharedText.reflowNotes(cut.notes)
            let nextLink = OpenableURL.from(item.urlString)?.absoluteString ?? item.urlString
            guard item.title != nextTitle || item.notes != nextNotes || item.urlString != nextLink else { continue }
            item.title = nextTitle
            item.notes = nextNotes
            item.urlString = nextLink
            PairSession.shared.noteLocalEdit(item, kind: "edit")
        }
    }

    /// Older installs may have sample rows with a missing or share-tracking Airbnb URL.
    private func repairSampleLinks() {
        guard !pairSession.isPaired else { return }
        for item in items {
            guard let seed = SampleData.matching(title: item.title) else { continue }
            let current = OpenableURL.from(item.urlString)?.absoluteString
            let expected = OpenableURL.from(seed.urlString)?.absoluteString ?? seed.urlString
            if current == expected { continue }
            item.urlString = expected
            PairSession.shared.noteLocalEdit(item, kind: "edit")
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
                let prev = to > 0 ? ordered[to - 1].sortOrder : nil
                let next = to < ordered.count - 1 ? ordered[to + 1].sortOrder : nil
                if let slot = ListReorder.slot(prev: prev, next: next) {
                    ordered[to].sortOrder = slot
                    PairSession.shared.noteLocalReorder(moved: ordered[to], others: [])
                } else {
                    let orders = ListReorder.rebalanced(ordered.count)
                    for (index, row) in ordered.enumerated() {
                        row.sortOrder = orders[index]
                    }
                    let moved = ordered[to]
                    PairSession.shared.noteLocalReorder(
                        moved: moved,
                        others: ordered.filter { $0.id != moved.id }
                    )
                }
            }
            reorderDrag = nil
        }
    }

    private func seedIfNeeded() {
        ItemStore.deduplicateSampleCopies(in: modelContext)

        // Paired phones use the shared iCloud list. Samples are only for a
        // fresh local install so they can be shown in Simulator / App Store.
        if pairSession.isPaired { return }

        let stored = ItemStore.allItems(in: modelContext)
        let oldThree = Set([
            "Lake Escape 2",
            "Greek Seas Charter Sailing",
            "Keto recipe",
        ])
        let titles = Set(stored.map(\.title))

        if stored.isEmpty {
            for (index, seed) in SampleData.seeds.enumerated() {
                modelContext.insert(SampleData.makeItem(seed, sortOrder: index))
            }
            return
        }

        if titles.isSubset(of: oldThree) {
            for item in stored {
                modelContext.delete(item)
            }
            for (index, seed) in SampleData.seeds.enumerated() {
                modelContext.insert(SampleData.makeItem(seed, sortOrder: index))
            }
            return
        }

        // Do not top up deleted samples. That recreated the trawler after the
        // user removed it and made "add" look like it duplicated the item.
    }

    private func importSharedDrafts() {
        var nextOrders: [ItemCategory: Int] = [:]
        for (payload, imageData) in ShareInbox.consumeDrafts() {
            let rawLink = payload.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            let link = OpenableURL.from(rawLink)?.absoluteString ?? rawLink
            var rawTitle = payload.title
            var rawNotes = payload.notes
            if InstagramShareText.isInstagramURL(link) || InstagramShareText.needsCleanup(title: rawTitle, notes: rawNotes) {
                let split = InstagramShareText.refine(title: rawTitle, notes: rawNotes)
                if !split.title.isEmpty { rawTitle = split.title }
                rawNotes = split.notes
            }
            if FacebookShareText.isFacebookURL(link) || rawTitle.lowercased().contains("on facebook") {
                let split = FacebookShareText.refine(title: rawTitle, notes: rawNotes)
                if !split.title.isEmpty { rawTitle = split.title }
                rawNotes = split.notes
            }
            let cut = SharedText.cutTitle(rawTitle, notes: rawNotes)
            let title = SharedText.normalized(cut.title)
            guard !title.isEmpty else { continue }
            let chosen = ItemCategory.parse(payload.category)
            let category = chosen.first ?? .places
            let sortOrder = nextOrders[category] ?? nextSortOrder(for: category)
            nextOrders[category] = sortOrder - 1
            let item = TodoItem(
                title: title,
                category: category,
                categories: chosen,
                urlString: link.isEmpty ? nil : link,
                imageData: imageData,
                notes: SharedText.reflowNotes(cut.notes),
                sortOrder: sortOrder,
                pairID: PairSession.shared.pairID
            )
            modelContext.insert(item)
            PairSession.shared.noteLocalEdit(item, kind: "add")
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
    var onDelete: (() -> Void)? = nil
    var onHandleDragChanged: ((CGFloat) -> Void)?
    var onHandleDragEnded: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(item.title)")
            }

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

            if item.chrisHearted || item.deenaHearted {
                HStack(spacing: 4) {
                    if item.chrisHearted {
                        Image(systemName: "heart.fill")
                    }
                    if item.deenaHearted {
                        Image(systemName: "heart.fill")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(heartPink)
                .accessibilityLabel("Hearted")
            }

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
    var preserveNewlines: Bool = false

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
        label.text = preserveNewlines ? SharedText.normalizedMultiline(text) : SharedText.normalized(text)
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
    @State private var browserPage: LinkBrowserPage?

    init(items: [TodoItem], selectedItem: Binding<TodoItem?>) {
        self.items = items
        self._selectedItem = selectedItem
        _selectedID = State(initialValue: selectedItem.wrappedValue?.id ?? items.first?.id ?? UUID())
    }

    var body: some View {
        TabView(selection: $selectedID) {
            ForEach(items, id: \.persistentModelID) { item in
                ItemDetailView(
                    item: item,
                    onEditingChange: { editing in
                        if item.id == selectedID {
                            isEditing = editing
                        }
                    },
                    onOpenLink: { url in
                        openLink(url)
                    }
                )
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Lock only the pager swipe. `.scrollDisabled` also freezes the item page itself.
        .background { PagingScrollLock(locked: isEditing) }
        .background(Palette.canvas(colorScheme).ignoresSafeArea())
        .onChange(of: selectedID) { _, newID in
            if let match = items.first(where: { $0.id == newID }) {
                selectedItem = match
            }
            isEditing = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .accessibilityHint(items.count > 1 ? "Swipe left or right to see other items" : "")
        .fullScreenCover(item: $browserPage) { page in
            LinkBrowserSheet(page: page) {
                browserPage = nil
            }
        }
    }

    private func openLink(_ url: URL) {
        if OpenableURL.isAirbnb(url) {
            OpenableURL.presentInSafari(url)
        } else {
            OpenableURL.openExternally(url)
        }
    }
}

/// Disables a `TabView` page swipe without turning off nested `ScrollView`s.
private struct PagingScrollLock: UIViewRepresentable {
    var locked: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let locked = locked
        DispatchQueue.main.async {
            var node: UIView? = uiView.superview
            while let view = node {
                let pagers = Self.pagingScrollViews(in: view)
                if !pagers.isEmpty {
                    for pager in pagers {
                        pager.isScrollEnabled = !locked
                    }
                    return
                }
                node = view.superview
            }
        }
    }

    private static func pagingScrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scroll = view as? UIScrollView, scroll.isPagingEnabled {
            found.append(scroll)
        }
        for child in view.subviews {
            found.append(contentsOf: pagingScrollViews(in: child))
        }
        return found
    }
}

struct ItemDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(PairSession.self) private var pairSession
    @Environment(HomeBase.self) private var homeBase
    @Bindable var item: TodoItem
    var onEditingChange: ((Bool) -> Void)? = nil
    var onOpenLink: ((URL) -> Void)? = nil
    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var draftLink = ""
    @State private var draftNotes = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var placeCaption: String?

    private var isGuest: Bool { pairSession.role == .deena }

    private var myHeart: Binding<Bool> {
        Binding(
            get: { isGuest ? item.deenaHearted : item.chrisHearted },
            set: { if isGuest { item.deenaHearted = $0 } else { item.chrisHearted = $0 } }
        )
    }

    private var partnerHeart: Binding<Bool> {
        Binding(
            get: { isGuest ? item.chrisHearted : item.deenaHearted },
            set: { if isGuest { item.chrisHearted = $0 } else { item.deenaHearted = $0 } }
        )
    }

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

                if !isEditing, savedURL != nil {
                    Button {
                        openSavedLink()
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Palette.brandBlue(colorScheme))
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Open link")
                }

                Button {
                    if isEditing {
                        commitEdits()
                    } else {
                        beginEditing()
                    }
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.brandBlue(colorScheme))
                        .frame(width: 32, height: 32)
                }
                .disabled(isEditing && draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(isEditing ? "Done editing" : "Edit item")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Palette.canvas(colorScheme))

            // Title sits above the ScrollView so link taps aren't eaten by
            // pager/scroll gestures. Keep the edit field in the same place.
            if isEditing {
                labeledField("Title") {
                    TextField("Title", text: $draftTitle, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...6)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .appCard(cornerRadius: 12, scheme: colorScheme)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            } else {
                titleView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    locationLine

                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            PartnerHeartButton(name: pairSession.myHeartLabel, isOn: myHeart, size: 18)
                            if pairSession.isPaired {
                                PairHeadButton(
                                    label: pairSession.myHeartLabel,
                                    tint: Color(red: 0.20, green: 0.48, blue: 0.98),
                                    size: 31,
                                    imageData: pairSession.headImageData(slot: .me)
                                ) {
                                    if pairSession.hasMultiplePairs {
                                        pairSession.switchToNextPair()
                                    }
                                }
                                .accessibilityLabel(
                                    pairSession.hasMultiplePairs
                                        ? "Switch list. You are \(pairSession.myHeartLabel)"
                                        : "You, \(pairSession.myHeartLabel)"
                                )
                            }
                        }
                        HStack(spacing: 6) {
                            PartnerHeartButton(
                                name: pairSession.partnerHeartLabel,
                                isOn: partnerHeart,
                                interactive: false,
                                size: 18
                            )
                            if pairSession.isPaired {
                                PairHeadButton(
                                    label: pairSession.partnerHeartLabel,
                                    tint: Color(red: 0.22, green: 0.78, blue: 0.55),
                                    size: 31,
                                    imageData: pairSession.headImageData(slot: .partner)
                                ) {
                                    if pairSession.hasMultiplePairs {
                                        pairSession.switchToNextPair()
                                    }
                                }
                                .accessibilityLabel(
                                    pairSession.hasMultiplePairs
                                        ? "Switch list. Current partner \(pairSession.partnerHeartLabel)"
                                        : "Partner \(pairSession.partnerHeartLabel)"
                                )
                            }
                        }
                        DoneCheckButton(isDone: $item.isDone, size: 18, name: "Done")
                    }
                    .frame(maxWidth: .infinity)
                    .onChange(of: item.chrisHearted) { _, _ in
                        PairSession.shared.noteLocalEdit(item, kind: "heart")
                    }
                    .onChange(of: item.deenaHearted) { _, _ in
                        PairSession.shared.noteLocalEdit(item, kind: "heart")
                    }
                    .onChange(of: item.isDone) { _, _ in
                        PairSession.shared.noteLocalEdit(item, kind: "edit")
                    }

                    photosBlock

                    if isEditing {
                        CategoryPickerGrid(selection: categoriesBinding)
                            .accessibilityLabel("Category")

                        labeledField("Link") {
                            TextField("https://", text: $draftLink)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .padding(12)
                                .appCard(cornerRadius: 12, scheme: colorScheme)
                        }

                        TextField("Add a note", text: $draftNotes, axis: .vertical)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(3...20)
                            .padding(12)
                            .appCard(cornerRadius: 12, scheme: colorScheme)
                    } else if !item.notes.isEmpty {
                        LockedText(
                            text: item.notes,
                            font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                            color: .label,
                            lines: 0,
                            preserveNewlines: true
                        )
                    }
                }
                .padding(20)
                .padding(.bottom, isEditing ? 180 : 0)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Palette.canvas(colorScheme).ignoresSafeArea())
        .onChange(of: photoItem) { _, newItem in
            Task { await applyPickedPhoto(newItem) }
        }
        .task(id: "\(item.id.uuidString)|\(item.urlString ?? "")|\(homeBase.latitude ?? 0)|\(homeBase.longitude ?? 0)") {
            await refreshPlaceLine()
        }
        .onDisappear {
            if isEditing { commitEdits() }
        }
        .onChange(of: isEditing) { _, editing in
            onEditingChange?(editing)
        }
    }

    private var savedURL: URL? {
        OpenableURL.from(item.urlString)
            ?? OpenableURL.from(item.notes)
            ?? OpenableURL.from(item.title)
            ?? OpenableURL.from(SampleData.matching(title: item.title)?.urlString)
    }

    private func openSavedLink() {
        guard let url = savedURL else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if item.urlString == nil || OpenableURL.from(item.urlString)?.absoluteString != url.absoluteString {
            item.urlString = url.absoluteString
            PairSession.shared.noteLocalEdit(item, kind: "edit")
        }
        if let onOpenLink {
            onOpenLink(url)
        } else {
            OpenableURL.presentInSafari(url)
        }
    }

    @ViewBuilder
    private var titleView: some View {
        let titleText = Text(verbatim: SharedText.normalized(item.title))
            .font(.body)
            .underline(savedURL != nil)
            .multilineTextAlignment(.leading)

        if savedURL != nil {
            Button(action: openSavedLink) {
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                        .foregroundStyle(Palette.brandBlue(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(savedURL?.host?.replacingOccurrences(of: "www.", with: "") ?? "Open link")
                        .font(.caption)
                        .foregroundStyle(Palette.brandBlue(colorScheme).opacity(0.8))
                }
                .padding(.top, 4)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open \(SharedText.normalized(item.title))")
            .accessibilityHint(savedURL?.absoluteString ?? "")
        } else {
            titleText
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var locationLine: some View {
        if let text = placeCaption {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.brandBlue(colorScheme))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityLabel(text)
        }
    }

    private func refreshPlaceLine() async {
        let source = "\(item.urlString ?? "")|\(item.title)"
        let cached: ItemPlace.Fix?
        if item.placeSource == source, let lat = item.placeLatitude, let lon = item.placeLongitude {
            cached = ItemPlace.Fix(latitude: lat, longitude: lon, locality: item.placeLocality)
        } else {
            cached = nil
        }
        let fix = await ItemPlace.resolve(
            urlString: item.urlString,
            title: item.title,
            cached: cached,
            cacheKey: cached == nil ? nil : source
        )
        guard let fix else {
            placeCaption = nil
            return
        }
        if item.placeSource != source
            || item.placeLatitude != fix.latitude
            || item.placeLongitude != fix.longitude
            || item.placeLocality != fix.locality {
            item.placeLatitude = fix.latitude
            item.placeLongitude = fix.longitude
            item.placeLocality = fix.locality
            item.placeSource = source
        }
        let miles = homeBase.miles(to: fix.latitude, longitude: fix.longitude)
        placeCaption = ItemPlace.line(locality: fix.locality, miles: miles)
    }

    private var categoriesBinding: Binding<Set<ItemCategory>> {
        Binding(
            get: { Set(item.categories) },
            set: { newValue in
                var next = item.categories.filter { newValue.contains($0) }
                for cat in ItemCategory.allCases where newValue.contains(cat) && !next.contains(cat) {
                    next.append(cat)
                }
                item.categories = next
                PairSession.shared.noteLocalEdit(item, kind: "edit")
            }
        )
    }

    @ViewBuilder
    private var photosBlock: some View {
        VStack(spacing: 14) {
            if item.hasPhoto {
                stackedPhotoCard(deleteLabel: "Delete photo", onDelete: clearPhoto) {
                    ItemPhotoView(item: item, cornerRadius: 18, placeholderIconSize: 48)
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipped()
                }
            }
            if item.hasExtraPhoto, let data = item.extraImageData, let image = UIImage(data: data) {
                stackedBitmap(image, deleteLabel: "Delete photo 2", onDelete: clearExtraPhoto)
            }
            if item.hasExtraPhoto2, let data = item.extraImageData2, let image = UIImage(data: data) {
                stackedBitmap(image, deleteLabel: "Delete photo 3", onDelete: clearExtraPhoto2)
            }
            if item.hasExtraPhoto3, let data = item.extraImageData3, let image = UIImage(data: data) {
                stackedBitmap(image, deleteLabel: "Delete photo 4", onDelete: clearExtraPhoto3)
            }
            if isEditing, item.photoCount < 4 {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                        Text(item.photoCount == 0 ? "Add photo" : "Add another photo")
                            .font(.headline)
                    }
                    .foregroundStyle(Palette.brandBlue(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .appCard(cornerRadius: 12, scheme: colorScheme)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.photoCount == 0 ? "Add photo" : "Add another photo")
            }
        }
    }

    private func stackedBitmap(_ image: UIImage, deleteLabel: String, onDelete: @escaping () -> Void) -> some View {
        stackedPhotoCard(deleteLabel: deleteLabel, onDelete: onDelete) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(image.size, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }

    private func stackedPhotoCard<Content: View>(
        deleteLabel: String,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            content()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .font(.system(size: 28, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(14)
                .accessibilityLabel(deleteLabel)
            }
        }
    }

    private func clearPhoto() {
        item.imageData = nil
        item.imageAssetName = nil
        item.imageURLString = nil
        photoItem = nil
        PairSession.shared.noteLocalEdit(item, kind: "edit")
    }

    private func applyPickedPhoto(_ picked: PhotosPickerItem?) async {
        guard let picked else { return }
        guard let data = try? await picked.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = PhotoJPEG.compressed(image) else { return }
        if !item.hasPhoto {
            item.imageData = jpeg
            item.imageAssetName = nil
            item.imageURLString = nil
        } else if !item.hasExtraPhoto {
            item.extraImageData = jpeg
        } else if !item.hasExtraPhoto2 {
            item.extraImageData2 = jpeg
        } else if !item.hasExtraPhoto3 {
            item.extraImageData3 = jpeg
        }
        photoItem = nil
        PairSession.shared.noteLocalEdit(item, kind: "edit")
    }

    private func clearExtraPhoto() {
        item.extraImageData = nil
        PairSession.shared.noteLocalEdit(item, kind: "edit")
    }

    private func clearExtraPhoto2() {
        item.extraImageData2 = nil
        PairSession.shared.noteLocalEdit(item, kind: "edit")
    }

    private func clearExtraPhoto3() {
        item.extraImageData3 = nil
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
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
        onEditingChange?(true)
    }

    private func commitEdits() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            let cut = SharedText.cutTitle(SharedText.normalized(trimmedTitle), notes: SharedText.normalizedMultiline(draftNotes))
            item.title = cut.title
            item.notes = cut.notes
        } else {
            item.notes = SharedText.normalizedMultiline(draftNotes)
        }
        let trimmedLink = draftLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLink.isEmpty {
            item.urlString = nil
        } else {
            item.urlString = OpenableURL.from(trimmedLink)?.absoluteString ?? trimmedLink
        }
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
            VStack(spacing: 1) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(isDone ? Palette.brandBlue(colorScheme) : Color.secondary.opacity(0.55))
                    .scaleEffect(isDone ? 1.06 : 1)
                if let name {
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: name == nil ? size + 8 : 44)
            .padding(.vertical, 0)
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
    var interactive: Bool = true
    var size: CGFloat = 34

    var body: some View {
        Group {
            if interactive {
                Button {
                    withAnimation(.spring(duration: 0.28)) {
                        isOn.toggle()
                    }
                } label: {
                    heartMark
                }
                .buttonStyle(.plain)
            } else {
                heartMark
            }
        }
        .accessibilityLabel("\(name) heart")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var heartMark: some View {
        VStack(spacing: 1) {
            Image(systemName: isOn ? "heart.fill" : "heart")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isOn ? heartPink : Color.secondary.opacity(0.55))
                .scaleEffect(isOn ? 1.06 : 1)
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
        .padding(.vertical, 0)
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
    @State private var selectedCategories: Set<ItemCategory> = [.places]
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isLoadingMeta = false
    @State private var isSaving = false
    @State private var lastFetchedLink = ""

    private var resolvedLink: String? {
        OpenableURL.from(urlString)?.absoluteString
            ?? OpenableURL.from(title)?.absoluteString
            ?? OpenableURL.from(notes)?.absoluteString
    }

    private var canSave: Bool {
        !isLoadingMeta && !isSaving && (
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || resolvedLink != nil
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        FindIdeasView { pageURL in
                            urlString = OpenableURL.from(pageURL)?.absoluteString ?? pageURL
                        }
                    } label: {
                        Label("Find Ideas", systemImage: "magnifyingglass")
                    }
                }

                Section("Or Paste a link") {
                    TextField("https://", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit {
                            Task { await prepareAndSave() }
                        }
                    if isLoadingMeta {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Getting title, photo, and notes…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

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

                    TextField("Title", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    CategoryPickerGrid(selection: $selectedCategories)
                }
            }
            .navigationTitle("Add item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await prepareAndSave() }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { selectedCategories = [category] }
            .onChange(of: photoItem) { _, newItem in
                Task { await loadPickedPhoto(newItem) }
            }
            .onChange(of: urlString) { _, _ in
                guard let link = resolvedLink, link != lastFetchedLink else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard resolvedLink == link else { return }
                    await enrichFromPage(saveIfReady: false)
                }
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

    @MainActor
    private func prepareAndSave() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        if let link = resolvedLink {
            urlString = link
        }

        if resolvedLink != nil {
            await enrichFromPage(saveIfReady: false)
        }
        saveOnce()
    }

    @MainActor
    private func enrichFromPage(saveIfReady: Bool) async {
        guard let link = resolvedLink else {
            if saveIfReady { saveOnce() }
            return
        }
        urlString = link
        if lastFetchedLink == link, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if saveIfReady { saveOnce() }
            return
        }
        isLoadingMeta = true
        lastFetchedLink = link
        let meta = await PageMetadata.fetch(from: link)
        if InstagramShareText.isInstagramURL(link) {
            let split = InstagramShareText.split(from: [
                title,
                notes,
                meta.title ?? "",
                meta.description ?? "",
            ])
            if !split.title.isEmpty {
                title = split.title
                selectedCategories.insert(ItemCategory.guessed(urlString: link, title: split.title + " " + split.notes))
            }
            notes = split.notes
        } else if FacebookShareText.isFacebookURL(link) {
            if PageMetadata.isPlaceholderTitle(title), let pageTitle = meta.title, !pageTitle.isEmpty {
                title = pageTitle
            }
            let split = FacebookShareText.split(from: [
                title,
                notes,
                meta.title ?? "",
                meta.description ?? "",
            ])
            if !split.title.isEmpty {
                title = split.title
                selectedCategories.insert(ItemCategory.guessed(urlString: link, title: split.title + " " + split.notes))
            }
            notes = split.notes
        } else {
            if PageMetadata.isPlaceholderTitle(title), let pageTitle = meta.title, !pageTitle.isEmpty {
                title = pageTitle
                selectedCategories.insert(ItemCategory.guessed(urlString: link, title: pageTitle))
            }
            if notes.isEmpty, let description = meta.description, !description.isEmpty {
                notes = description
            }
        }
        let cut = SharedText.cutTitle(title, notes: notes)
        title = cut.title
        notes = cut.notes
        // Keep the clean link even if metadata parsing touched other fields.
        urlString = link
        if photoData == nil, let image = meta.image, let jpeg = PhotoJPEG.compressed(image) {
            photoData = jpeg
        }
        isLoadingMeta = false
        if saveIfReady {
            saveOnce()
        }
    }

    @MainActor
    private func saveOnce() {
        var trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedLink = resolvedLink ?? ""

        if let extracted = OpenableURL.firstRawHTTPURL(in: trimmedTitle) {
            trimmedTitle = trimmedTitle.replacingOccurrences(of: extracted, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLink.isEmpty {
                trimmedLink = OpenableURL.from(extracted)?.absoluteString ?? extracted
            }
        }
        if let clean = OpenableURL.from(trimmedLink) {
            trimmedLink = clean.absoluteString
        }
        if trimmedTitle.isEmpty, let url = URL(string: trimmedLink) {
            trimmedTitle = url.host?.replacingOccurrences(of: "www.", with: "") ?? "Saved link"
        }
        guard !trimmedTitle.isEmpty else { return }

        let cut = SharedText.cutTitle(SharedText.normalized(trimmedTitle), notes: SharedText.reflowNotes(notes))
        let chosen = selectedCategories.isEmpty ? [category] : ItemCategory.allCases.filter { selectedCategories.contains($0) }
        let primary = chosen.first ?? category
        let nextSortOrder = (items.filter {
            ($0.pairID == PairSession.shared.pairID || $0.pairID.isEmpty || PairSession.shared.pairID == nil)
                && $0.belongs(to: primary)
        }.map(\.sortOrder).min() ?? 0) - 1
        let item = TodoItem(
            title: cut.title,
            category: primary,
            categories: chosen,
            urlString: trimmedLink.lowercased().hasPrefix("http") ? trimmedLink : nil,
            imageData: photoData,
            notes: cut.notes,
            sortOrder: nextSortOrder,
            pairID: PairSession.shared.pairID
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
                .foregroundStyle(item.category.iconColor)
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
