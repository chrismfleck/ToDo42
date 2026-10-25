import EventKit
import EventKitUI
import UIKit

/// Presents the system New Event sheet with Save4Two item fields prefilled.
enum CalendarEventHandoff {
    struct Draft {
        var title: String
        var notes: String
        var url: URL?
        var location: String?
    }

    @MainActor
    static func present(draft: Draft) async -> String? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return "Add a title first, then tap Calendar."
        }
        guard let host = topViewController() else {
            return "Couldn't open Calendar on this screen."
        }

        let store = EKEventStore()
        let allowed: Bool
        do {
            // Full access so the system New Event sheet can list calendars.
            if #available(iOS 17.0, *) {
                allowed = try await store.requestFullAccessToEvents()
            } else {
                allowed = try await store.requestAccess(to: .event)
            }
        } catch {
            return "Couldn't get Calendar access. Check Settings → Save4Two."
        }
        guard allowed else {
            return "Allow Calendar access in Settings to add this item."
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = true
        let dayStart = Calendar.current.startOfDay(for: Date())
        event.startDate = dayStart
        event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        var noteParts: [String] = []
        let trimmedNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            noteParts.append(trimmedNotes)
        }
        if let url = draft.url {
            event.url = url
            let urlText = url.absoluteString
            if trimmedNotes.range(of: urlText, options: .caseInsensitive) == nil {
                noteParts.append(urlText)
            }
        }
        if !noteParts.isEmpty {
            event.notes = noteParts.joined(separator: "\n\n")
        }
        if let location = draft.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            event.location = location
        }

        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = event
        EventEditBridge.retain(editor)
        host.present(editor, animated: true)
        return nil
    }

    @MainActor
    private static func topViewController(
        base: UIViewController? = {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }()
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

/// Keeps the edit delegate alive until the sheet is dismissed.
private final class EventEditBridge: NSObject, EKEventEditViewDelegate {
    private static var active: EventEditBridge?
    private weak var editor: EKEventEditViewController?

    static func retain(_ editor: EKEventEditViewController) -> EventEditBridge {
        let bridge = EventEditBridge()
        bridge.editor = editor
        editor.editViewDelegate = bridge
        active = bridge
        return bridge
    }

    func eventEditViewController(
        _ controller: EKEventEditViewController,
        didCompleteWith action: EKEventEditViewAction
    ) {
        controller.dismiss(animated: true) {
            if EventEditBridge.active === self {
                EventEditBridge.active = nil
            }
        }
    }
}
