import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("How to use Save 4 Two")
                        .font(.title2.bold())

                    openingScreenshot

                    VStack(alignment: .leading, spacing: 18) {
                        HelpStep(
                            number: 1,
                            spoken: "To add an item, tap plus paste a link. Title, photo, and notes auto fill in. Or skip the link and type the details and save. Then tap check for home page."
                        ) {
                            helpText("To add an item, tap ")
                            + chrome("plus.circle.fill")
                            + helpText(" paste a link. Title, photo, and notes auto fill in. Or skip the link and type the details and save. Then tap ")
                            + chrome("checkmark")
                            + helpText(" for home page.")
                        }

                        HelpStep(
                            number: 2,
                            spoken: "To add a partner tap the pair icon. Enter names, send invite to partner. Or enter a code if you are sent one."
                        ) {
                            helpText("To add a partner tap ")
                            + chrome("person.2")
                            + helpText(". Enter names, send invite to partner. Or enter a code if you are sent one.")
                        }

                        HelpStep(
                            number: 3,
                            spoken: "From a page on Instagram or TikTok, tap Share, then Share to. Look for the Save 4 Two app icon. You may need to swipe left."
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                helpText("From a page on Instagram or TikTok etc, tap ")
                                + chrome("paperplane")
                                + helpText(" then ")
                                + chrome("square.and.arrow.up")
                                + helpText(". Look for ")
                                + helpText("Save 4 Two")
                                    .fontWeight(.semibold)
                                + helpText(" — you may need to swipe left.")
                                Image("HelpAppIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .accessibilityHidden(true)
                            }
                        }

                        HelpStep(
                            number: 4,
                            spoken: "Wait for the photo if it is still loading. Review or edit the page, select a category, tap Save."
                        ) {
                            helpText("Wait for the photo if it is still loading. Review or edit the page, select a category, tap Save.")
                        }

                        HelpStep(
                            number: 5,
                            spoken: "In list view, items can be reordered by tapping the gear and dragging the hamburger handle up or down. Then tap the check."
                        ) {
                            helpText("In list view, items can be reordered by tapping ")
                            + chrome("gearshape")
                            + helpText(" and dragging ")
                            + chrome("line.3.horizontal")
                            + helpText(" up or down. Then tap ")
                            + chrome("checkmark")
                            + helpText(".")
                        }

                        HelpStep(
                            number: 6,
                            spoken: "To edit an item, tap it in the list, then tap the gear on that page. Details can be edited and an extra photo can be added and saved for a fun memory. Tap your heart so your partner sees you like it. Tap the check when you are done."
                        ) {
                            helpText("To edit an item, tap it in the list, then tap ")
                            + chrome("gearshape")
                            + helpText(" on that page. Details can be edited and an extra photo can be added and saved for a fun memory. Tap your heart so your partner sees you like it. Tap ")
                            + chrome("checkmark")
                            + helpText(" when you are done.")
                        }

                        HelpStep(
                            number: 7,
                            spoken: "To delete an item from the home page, tap the gear, tap the red minus, then tap the check to save."
                        ) {
                            helpText("To delete item from home page, tap ")
                            + chrome("gearshape")
                            + helpText(", tap ")
                            + redChrome("minus.circle.fill")
                            + helpText(", tap ")
                            + chrome("checkmark")
                            + helpText(" to save.")
                        }

                        HelpStep(
                            number: 8,
                            spoken: "When your partner adds, hearts, or edits, a lock-screen banner says Save 4 Two, Your list was updated. Allow notifications when asked."
                        ) {
                            helpText("When your partner adds, hearts, or edits, a lock-screen banner says Save 4 Two — Your list was updated. Allow notifications when asked.")
                        }
                    }

                    footer
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Palette.canvas(colorScheme).ignoresSafeArea())
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(Palette.brandBlue(colorScheme))
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
            .accessibilityLabel("Screenshot of the home list in edit mode")
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
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if build.isEmpty {
            return "Version \(short)"
        }
        return "Version \(short) (\(build))"
    }

    private func helpText(_ string: String) -> Text {
        Text(string)
    }

    private func chrome(_ systemName: String) -> Text {
        Text(Image(systemName: systemName))
            .font(.body.weight(.semibold))
            .foregroundColor(Palette.brandBlue(colorScheme))
    }

    private func redChrome(_ systemName: String) -> Text {
        Text(Image(systemName: systemName))
            .font(.body.weight(.semibold))
            .foregroundColor(.red)
    }
}

private struct HelpStep<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let number: Int
    var spoken: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Palette.brandBlue(colorScheme))
                .frame(width: 26, alignment: .leading)
                .accessibilityHidden(true)
            content
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(number). \(spoken)")
    }
}

#Preview {
    HelpView()
        .preferredColorScheme(.dark)
}
