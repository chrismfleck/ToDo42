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
                            spoken: "Tap the pair icon. Enter names, send invite to partner. Or enter a code if you are sent one."
                        ) {
                            helpText("Tap ")
                            + chrome("person.2")
                            + helpText(" Enter names, send invite to partner. Or enter a code if you are sent one.")
                        }

                        HelpStep(
                            number: 2,
                            spoken: "From a page on Instagram or TikTok, tap Share, then Share to."
                        ) {
                            helpText("From a page on Instagram or TikTok etc, tap ")
                            + chrome("paperplane")
                            + helpText(" then ")
                            + chrome("square.and.arrow.up")
                            + helpText(".")
                        }

                        HelpStep(
                            number: 3,
                            spoken: "Look for the Save4Two app icon. You may need to swipe left."
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                helpText("Look for ")
                                + helpText("Save4Two")
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
                            spoken: "Review or edit the page, select a category, tap Save."
                        ) {
                            helpText("Review or edit the page, select a category, tap Save.")
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
                            spoken: "To enter a new item manually, tap plus, fill in the detail fields, then tap Save."
                        ) {
                            helpText("To enter a new item manually, tap ")
                            + chrome("plus.circle.fill")
                            + helpText(" and fill in the detail fields, then tap Save.")
                        }

                        HelpStep(
                            number: 7,
                            spoken: "To edit an item, tap it in the list, then tap the gear on that page. Details can be edited and an extra photo can be added and saved for a fun memory. Tap the check when you are done. If you see red minus buttons, tap the check first so items can be opened."
                        ) {
                            helpText("To edit an item, tap it in the list, then tap ")
                            + chrome("gearshape")
                            + helpText(" on that page. Details can be edited and an extra photo can be added and saved for a fun memory. Tap ")
                            + chrome("checkmark")
                            + helpText(" when you are done. If you see red minus buttons, tap the check first so items can be opened.")
                        }
                    }

                    Link(destination: URL(string: "https://save4two.com")!) {
                        Text("save4two.com")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 8)
                    .accessibilityLabel("Open save4two.com")

                    Text(versionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(versionText)
                }
                .padding(20)
                .padding(.bottom, 16)
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

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "Version \(version) (\(build))"
    }

    private var openingScreenshot: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Opening page")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
                .accessibilityLabel("Screenshot of the opening list page in edit mode")
        }
    }

    private func helpText(_ string: String) -> Text {
        Text(string)
    }

    private func chrome(_ systemName: String) -> Text {
        Text(Image(systemName: systemName))
            .font(.body.weight(.semibold))
            .foregroundColor(Palette.brandBlue(colorScheme))
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
