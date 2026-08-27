import SwiftUI
import SwiftData

@main
struct ToDo42App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(PaletteHost())
        }
        .modelContainer(for: TodoItem.self)
    }
}

private struct PaletteHost: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Palette.canvas(colorScheme).ignoresSafeArea()
    }
}

