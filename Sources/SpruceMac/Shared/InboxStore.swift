import Foundation
import Observation
import SpruceCore

/// One message in Spruce's in-app Notification Center (the bell in the sidebar).
public struct InboxItem: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Monitor and protection alerts.
        case alert
        /// Scheduled reminders (weekly Checkup).
        case reminder
        /// A finished Checkup or cleanup.
        case result
        /// A suggestion from Spruce itself (never offers or news).
        case tip

        public var symbol: String {
            switch self {
            case .alert: return "exclamationmark.triangle"
            case .reminder: return "calendar.badge.clock"
            case .result: return "checkmark.seal"
            case .tip: return "lightbulb"
            }
        }
    }

    /// Same id as the system notification it mirrors (posting again replaces it).
    public var id: String
    public var kind: Kind
    public var date: Date
    public var title: String
    public var body: String
    /// `ModuleID` raw value to open when clicked.
    public var module: String?
    /// Tool id to open when clicked.
    public var tool: String?
    public var isRead: Bool

    public init(id: String = UUID().uuidString, kind: Kind, date: Date = Date(), title: String, body: String,
                module: String? = nil, tool: String? = nil, isRead: Bool = false) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.body = body
        self.module = module
        self.tool = tool
        self.isRead = isRead
    }
}

/// Keeps alerts, reminders and results so a banner that was swiped away (or muted by
/// Focus) can be found again in the app. At most 200 items, for 60 days. Changes are
/// applied on the main thread.
@Observable
public final class InboxStore {
    public static let shared = InboxStore()
    public static let maxItems = 200
    public static let maxAge: TimeInterval = 60 * 24 * 3600

    /// Newest first.
    public private(set) var items: [InboxItem]

    private let store: JSONFileStore<[InboxItem]>

    public init(url: URL = SprucePaths.applicationSupport.appendingPathComponent("inbox.json")) {
        store = JSONFileStore(url: url, prettyPrinted: false)
        items = Self.pruned(store.load() ?? [])
    }

    public var unreadCount: Int { items.filter { !$0.isRead }.count }
    public var hasUnread: Bool { items.contains { !$0.isRead } }

    /// Adds `item`, replacing an item with the same id (it becomes unread again).
    public func add(_ item: InboxItem) {
        mutate { items in
            items.removeAll { $0.id == item.id }
            items.insert(item, at: 0)
        }
    }

    /// Adds `item` only when no item with its id exists yet (delivered-notification sync).
    public func addIfMissing(_ item: InboxItem) {
        mutate { items in
            guard !items.contains(where: { $0.id == item.id }) else { return }
            items.append(item)
            items.sort { $0.date > $1.date }
        }
    }

    public func markRead(id: String) {
        mutate { items in
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].isRead = true }
        }
    }

    public func markAllRead() {
        mutate { items in
            for index in items.indices { items[index].isRead = true }
        }
    }

    public func remove(id: String) {
        mutate { items in items.removeAll { $0.id == id } }
    }

    public func clearAll() {
        mutate { items in items.removeAll() }
    }

    // MARK: Private

    private func mutate(_ change: @escaping (inout [InboxItem]) -> Void) {
        let apply = { [weak self] in
            guard let self else { return }
            var copy = self.items
            change(&copy)
            copy = Self.pruned(copy)
            guard copy != self.items else { return }
            self.items = copy
            try? self.store.save(copy)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private static func pruned(_ items: [InboxItem]) -> [InboxItem] {
        let cutoff = Date().addingTimeInterval(-maxAge)
        return Array(items.filter { $0.date >= cutoff }.prefix(maxItems))
    }
}
