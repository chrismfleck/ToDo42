import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@main
struct ToDo42App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer = {
        // Keep lists on the phone. Pairing uses CloudKit by itself; SwiftData
        // must not switch to an empty iCloud store when that entitlement is on.
        let config = ModelConfiguration(cloudKitDatabase: .none)
        let container = try! ModelContainer(for: TodoItem.self, configurations: config)
        ItemStore.deduplicate(in: container.mainContext)
        return container
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(PaletteHost())
                .environment(PairSession.shared)
        }
        .modelContainer(modelContainer)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(name: .todo42CloudPush, object: userInfo)
        completionHandler(.newData)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension Notification.Name {
    static let todo42CloudPush = Notification.Name("todo42CloudPush")
}

private struct PaletteHost: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Palette.canvas(colorScheme).ignoresSafeArea()
    }
}
