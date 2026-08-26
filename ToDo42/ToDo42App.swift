import SwiftUI
import SwiftData

@main
struct ToDo42App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TodoItem.self)
    }
}

