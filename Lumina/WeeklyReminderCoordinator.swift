import Foundation
import Observation
import UserNotifications

@MainActor
protocol WeeklyReminderClient {
    func pendingIdentifiers() async -> [String]
    func isAuthorized(requestIfNeeded: Bool) async throws -> Bool
    func schedule(identifier: String) async throws
    func remove(identifiers: [String])
}

/// One application-owned coordinator survives a journal/session replacement.
/// Every change gets a distinct request ID: an old add callback can remove only
/// its own request, never a reminder enabled by a later user action.
@MainActor
@Observable
final class WeeklyReminderCoordinator {
    static let enabledKey = "remindersEnabled"
    static let requestKey = "weeklyReminderRequestIdentifier"
    static let legacyIdentifier = "coach-weekly"
    static let identifierPrefix = "lumina-weekly-"

    private(set) var isEnabled: Bool
    private(set) var isUpdating = false
    var errorMessage: String?

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let client: any WeeklyReminderClient
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var inFlightIdentifiers: Set<String> = []
    @ObservationIgnored private var hasStarted = false

    init(preferences: UserDefaults, client: any WeeklyReminderClient) {
        self.preferences = preferences
        self.client = client
        isEnabled = preferences.bool(forKey: Self.enabledKey)
    }

    @discardableResult
    func refreshWithoutPrompt() -> Task<Void, Never> {
        // A delayed launch bootstrap must not supersede an explicit choice or
        // a permission dialog already started by the user in Settings.
        guard !hasStarted else { return Task { } }
        return setEnabled(isEnabled, requestIfNeeded: false)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, requestIfNeeded: Bool = true) -> Task<Void, Never> {
        let token = UUID()
        let identifier: String? = enabled ? Self.identifierPrefix + UUID().uuidString : nil
        var oldIdentifiers = inFlightIdentifiers
        oldIdentifiers.insert(Self.legacyIdentifier)
        if let previous = preferences.string(forKey: Self.requestKey), Self.owns(previous) {
            oldIdentifiers.insert(previous)
        }

        // Invalidate and persist synchronously, before a permission/scheduling
        // callback can return. Turning off never waits for a system dialog.
        revision = token
        hasStarted = true
        isEnabled = enabled
        isUpdating = enabled
        errorMessage = nil
        preferences.set(enabled, forKey: Self.enabledKey)
        if let identifier {
            preferences.set(identifier, forKey: Self.requestKey)
            inFlightIdentifiers.insert(identifier)
        } else {
            preferences.removeObject(forKey: Self.requestKey)
        }
        client.remove(identifiers: oldIdentifiers.sorted())

        return Task { @MainActor in
            defer {
                if let identifier { inFlightIdentifiers.remove(identifier) }
                if revision == token { isUpdating = false }
            }
            // Reconcile requests retained from an earlier launch, including the
            // old fixed identifier, without deleting unrelated app reminders.
            let pending = await client.pendingIdentifiers()
            guard revision == token else { return }
            client.remove(identifiers: pending.filter { Self.owns($0) && $0 != identifier })
            guard let identifier else { return }
            do {
                let authorized = try await client.isAuthorized(requestIfNeeded: requestIfNeeded)
                guard revision == token && isEnabled else { return }
                guard authorized else {
                    failCurrentChange(token, identifier: identifier,
                        message: L("Reminders are off. Allow notifications in iOS Settings, then turn this reminder on."))
                    return
                }
                try await client.schedule(identifier: identifier)
                guard revision == token && isEnabled else {
                    client.remove(identifiers: [identifier])
                    return
                }
            } catch {
                // A stale request must clean up only its unique ID. A newer
                // request may already have completed and must remain scheduled.
                client.remove(identifiers: [identifier])
                failCurrentChange(token, identifier: identifier,
                    message: L("Could not enable the weekly reminder: %@", error.localizedDescription))
            }
        }
    }

    private static func owns(_ identifier: String) -> Bool {
        identifier == legacyIdentifier || identifier.hasPrefix(identifierPrefix)
    }

    private func failCurrentChange(_ token: UUID, identifier: String, message: String) {
        guard revision == token else { return }
        isEnabled = false
        preferences.set(false, forKey: Self.enabledKey)
        preferences.removeObject(forKey: Self.requestKey)
        client.remove(identifiers: [identifier])
        errorMessage = message
    }
}

@MainActor
struct SystemWeeklyReminderClient: WeeklyReminderClient {
    private let center = UNUserNotificationCenter.current()

    func pendingIdentifiers() async -> [String] {
        let requests = await center.pendingNotificationRequests()
        return requests.map(\.identifier)
    }

    func isAuthorized(requestIfNeeded: Bool) async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined where requestIfNeeded:
            return try await center.requestAuthorization(options: [.alert, .sound])
        default:
            return false
        }
    }

    func schedule(identifier: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = L("Lumina journal")
        content.body = L("Would you like to review your week or add a journal entry?")
        content.sound = .default
        var date = DateComponents()
        date.weekday = 1
        date.hour = 19
        try await center.add(UNNotificationRequest(identifier: identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)))
    }

    func remove(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
