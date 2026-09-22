import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CategoryNames.self) private var categoryNames
    @Environment(HomeBase.self) private var homeBase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center, spacing: 6) {
                        Text("How to use Save 4 Two")
                            .font(.system(size: 18, weight: .regular))
                        Image("HelpAppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: Self.helpAppIconSize, height: Self.helpAppIconSize)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .accessibilityHidden(true)
                    }

                    openingScreenshot

                    VStack(alignment: .leading, spacing: 18) {
                        HelpStep(
                            number: 1,
                            spoken: "To add an item, tap plus paste a link. Title, photo, and notes auto fill in. Or skip the link and type the details and save. Then tap check for home page."
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .center, spacing: 5) {
                                    helpText("To add an item, tap")
                                    chromePlus
                                }
                                helpText("Paste a link. Title, photo, and notes auto fill in. Or skip the link and type the details and save.")
                                HStack(alignment: .center, spacing: 5) {
                                    helpText("Then tap")
                                    chromeCheck
                                    helpText("for home page.")
                                }
                            }
                        }

                        HelpStep(
                            number: 2,
                            spoken: "To find ideas tap plus."
                        ) {
                            HStack(alignment: .center, spacing: 5) {
                                helpText("To find ideas tap")
                                chromePlus
                            }
                        }

                        HelpStep(
                            number: 3,
                            spoken: "To add a partner tap the circled double hearts. Enter names and headshots, send invite to partner. Or enter a code if you are sent one. To add second partner tap Add a pair."
                        ) {
                            partnerHelpRow
                        }

                        HelpStep(
                            number: 4,
                            spoken: "From a page on Instagram or TikTok, tap Share, then Share to. Look for the Save 4 Two app icon. You may need to swipe left and or tap the circle with three dots."
                        ) {
                            shareToHelpRow
                        }

                        HelpStep(
                            number: 5,
                            spoken: "Wait for the photo if it is still loading. Review or edit the page, tap every category where it should appear, tap Save."
                        ) {
                            helpText("Wait for the photo if it is still loading. Review or edit the page, tap every category where it should appear, tap Save.")
                        }

                        HelpStep(
                            number: 6,
                            spoken: "In list view, items can be reordered by tapping the pencil and dragging the hamburger handle up or down. Then tap the check."
                        ) {
                            helpText("In list view, items can be reordered by tapping ")
                            + chrome("pencil.circle")
                            + helpText(" and dragging ")
                            + chrome("line.3.horizontal")
                            + helpText(" up or down. Then tap ")
                            + chrome("checkmark.circle")
                            + helpText(".")
                        }

                        HelpStep(
                            number: 7,
                            spoken: "To edit an item, tap it in the list, then tap the pencil on that page. Details can be edited and the original plus three more photos can be added. Tap your heart so your partner sees you like it. Tap the check when you are done."
                        ) {
                            helpText("To edit an item, tap it in the list, then tap ")
                            + chrome("pencil.circle")
                            + helpText(" on that page. Details can be edited and the original plus three more photos can be added. Tap your heart so your partner sees you like it. Tap ")
                            + chrome("checkmark.circle")
                            + helpText(" when you are done.")
                        }

                        HelpStep(
                            number: 8,
                            spoken: "To delete an item from the home page, tap the pencil, tap the red minus, then tap the check to save. Either person can delete."
                        ) {
                            helpText("To delete item from home page, tap ")
                            + chrome("pencil.circle")
                            + helpText(", tap ")
                            + redChrome("minus.circle.fill")
                            + helpText(", tap ")
                            + chrome("checkmark.circle")
                            + helpText(" to save. Either person can delete.")
                        }

                        HelpStep(
                            number: 9,
                            spoken: "Enter additional categories. Swipe across three home pages: Bed Fun and Table, then Projects Recipe and Health, then Vegas London and DC trips. You can rename all nine.",
                            isolatesAccessibility: false
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                helpText("Enter additional categories. Swipe left on the home list for more tabs. Names below are the tab titles — tap to edit.")
                                ForEach(Array(ItemCategory.pages.enumerated()), id: \.offset) { _, page in
                                    categoryNameFields(page)
                                }
                            }
                        }

                        HelpStep(
                            number: 10,
                            spoken: "When your partner adds, hearts, edits, reorders, or deletes, a lock-screen banner says Save 4 Two, Your list was updated. Allow notifications when asked."
                        ) {
                            helpText("When your partner adds, hearts, edits, reorders, or deletes, a lock-screen banner says Save 4 Two — Your list was updated. Allow notifications when asked.")
                        }

                        HelpStep(
                            number: 11,
                            spoken: "Set home base, optional. Tap Set home while you are at home so item pages can show the town and how many miles away they are.",
                            isolatesAccessibility: false
                        ) {
                            homeBaseStep
                        }
                    }

                    footer
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AppCanvasBackground().ignoresSafeArea() }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onDisappear {
                categoryNames.flushUpload()
            }
        }
        .tint(Palette.brandBlue(colorScheme))
    }

    private var partnerHelpRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 5) {
                helpText("To add a partner tap")
                PairHeartPlusIcon(size: Self.helpChromeSize, tint: Palette.brandBlue(colorScheme))
            }
            helpText("Enter names and headshots, send invite to partner. Or enter a code if you are sent one.")
            helpText("To add second partner tap Add a pair.")
        }
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var shareToHelpRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            (
                helpText("From a page on Instagram or TikTok etc, tap ")
                + chrome("paperplane")
                + helpText(" then ")
                + chrome("square.and.arrow.up")
                + helpText(".")
            )
            .fixedSize(horizontal: false, vertical: true)

            // Icon sits after “Save 4 Two”; text can wrap onto the next line around it.
            HStack(alignment: .center, spacing: 6) {
                helpText("Look for Save 4 Two")
                Image("HelpAppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.helpAppIconSize, height: Self.helpAppIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 5) {
                helpText("You may need to swipe left and/or tap")
                chrome("ellipsis.circle")
                helpText(".")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Help body copy — regular 18pt.
    private static let helpBodySize: CGFloat = 18
    private static let helpChromeSize: CGFloat = 22
    private static let helpChromeLine: CGFloat = 22 * 0.054
    private static let helpAppIconSize: CGFloat = 26

    private var chromePlus: some View {
        ChromeCircleIcon(
            systemName: "plus",
            diameter: Self.helpChromeSize,
            tint: Palette.brandBlue(colorScheme),
            lineWidth: Self.helpChromeLine
        )
        .accessibilityHidden(true)
    }

    private var chromeCheck: some View {
        ChromeCircleIcon(
            systemName: "checkmark",
            diameter: Self.helpChromeSize,
            tint: Palette.brandBlue(colorScheme),
            lineWidth: Self.helpChromeLine
        )
        .accessibilityHidden(true)
    }

    private func categoryNameFields(_ categories: [ItemCategory]) -> some View {
        VStack(spacing: 8) {
            ForEach(categories) { cat in
                HStack(spacing: 10) {
                    Image(systemName: cat.systemImage)
                        .font(.system(size: Self.helpBodySize, weight: .regular))
                        .foregroundStyle(cat.iconColor)
                        .frame(width: 22)
                    TextField(cat.defaultTitle, text: categoryNames.binding(for: cat))
                        .font(.system(size: Self.helpBodySize, weight: .regular))
                        .textInputAutocapitalization(.words)
                        .padding(10)
                        .appCard(cornerRadius: 10, scheme: colorScheme)
                }
            }
        }
    }

    private var homeBaseStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set home base (optional). Tap Set home while you are at home so item pages can show the town and how many miles away they are.")
                .font(.system(size: Self.helpBodySize, weight: .regular))
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: Self.helpBodySize, weight: .regular))
                    .foregroundStyle(Palette.brandBlue(colorScheme))
                Text(homeBase.isSet ? "Home: \(homeBase.displayLabel)" : "Home: not set")
                    .font(.system(size: Self.helpBodySize, weight: .regular))
            }
            Button {
                Task { await homeBase.setFromCurrentLocation() }
            } label: {
                Text(homeBase.isSetting ? "Setting home…" : "Set home")
                    .font(.system(size: Self.helpBodySize, weight: .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .appCard(cornerRadius: 12, scheme: colorScheme)
            }
            .buttonStyle(.plain)
            .disabled(homeBase.isSetting)
            .accessibilityLabel("Set home")
            if !homeBase.statusMessage.isEmpty {
                Text(homeBase.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var openingScreenshot: some View {
        Image("HelpOpening")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Palette.isDark(colorScheme) ? Color.white.opacity(0.16) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            }
            .accessibilityLabel("Screenshot of the home header and category tabs")
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text(versionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link(destination: URL(string: "https://save4two.com")!) {
                Text("save4two.com")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Open save4two.com")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var versionText: String {
        AppBuild.versionLine
    }

    private func helpText(_ string: String) -> Text {
        Text(string)
            .font(.system(size: Self.helpBodySize, weight: .regular))
    }

    private func chrome(_ systemName: String) -> Text {
        Text(Image(systemName: systemName))
            .font(.system(size: Self.helpBodySize, weight: .regular))
            .foregroundColor(Palette.brandBlue(colorScheme))
    }

    private func redChrome(_ systemName: String) -> Text {
        Text(Image(systemName: systemName))
            .font(.system(size: Self.helpBodySize, weight: .regular))
            .foregroundColor(.red)
    }
}

private struct HelpStep<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let number: Int
    var spoken: String
    var isolatesAccessibility = true
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.system(size: 18, weight: .regular).monospacedDigit())
                .foregroundStyle(Palette.brandBlue(colorScheme))
                .frame(width: 28, alignment: .leading)
                .accessibilityHidden(true)
            content
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(isolatesAccessibility)
        }
        .modifier(HelpStepAccess(isolates: isolatesAccessibility, label: "\(number). \(spoken)"))
    }
}

private struct HelpStepAccess: ViewModifier {
    var isolates: Bool
    var label: String

    func body(content: Content) -> some View {
        if isolates {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        } else {
            content
        }
    }
}

#Preview {
    HelpView()
        .environment(CategoryNames.shared)
        .environment(HomeBase.shared)
        .preferredColorScheme(.dark)
}
