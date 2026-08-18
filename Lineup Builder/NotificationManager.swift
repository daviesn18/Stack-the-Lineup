import UserNotifications
import os

// MARK: - NotificationManager
//
// Handles UNUserNotification permission and posts notification trigger
// events to the Cloudflare Worker, which sends real APNs pushes to
// all other coaches on the team.
//
// Local notifications are no longer used for coach-to-coach events.
// The Worker sends APNs alerts that arrive at the lock screen like
// any other push notification.

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    // Replace with your deployed Cloudflare Worker URL after running `wrangler deploy`.
    // Format: https://stl-push-worker.<your-subdomain>.workers.dev
    private let workerURL = "https://stl-push-worker.stackthelineup.workers.dev"

    private let permissionKey = "hasRequestedNotificationPermission"

    private override init() {
        super.init()
        installDelegate()
    }

    /// Registers as the notification-center delegate. Idempotent.
    ///
    /// Called from `init`, and again from `didFinishLaunchingWithOptions` — the
    /// call that actually matters. See the comment there: a tap that cold-launches
    /// the app is delivered before any view exists, and this type is a lazy static
    /// whose first touch used to be a view lifecycle. Exposed as a method rather
    /// than left to `init`'s side effect so the call site reads as intent, and so
    /// moving the assignment later cannot quietly break the cold-launch path.
    func installDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows APNs notifications as banners even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let eventType = notification.request.content.userInfo["eventType"] as? String ?? "unknown"
        Task { @MainActor in
            Analytics.signal("push.received", parameters: [
                "eventType": eventType,
                "state": "foreground"
            ])
        }
        completionHandler([.banner, .sound])
    }

    /// Fired when the user taps a notification (from lock screen, banner, or
    /// notification center). This is the common delivery path, since most
    /// pushes arrive while the app is backgrounded.
    ///
    /// Brings the team the push was about to the front. Until this routed, the
    /// tap did nothing but open the app wherever it was left — a coach told
    /// that something happened on Team C landed on Team A and had to find the
    /// switcher themselves. Backlog 3.10.
    ///
    /// `teamID` has been in every payload since the Worker was written; it sits
    /// at the top level beside `aps`, which is where APNs puts custom keys into
    /// `userInfo`. So this needs nothing from the Worker and works for pushes
    /// already sitting on a lock screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let eventType = userInfo["eventType"] as? String ?? "unknown"
        let teamID = (userInfo["teamID"] as? String).flatMap(UUID.init(uuidString:))

        Task { @MainActor in
            Analytics.signal("push.received", parameters: [
                "eventType": eventType,
                "state": "tapped"
            ])

            // Routed through AppRouter rather than acted on directly, because a
            // tap from the lock screen usually cold-launches the app and there
            // is no view hierarchy yet to receive it. The shared router holds
            // the request until one appears — the same handoff Siri and
            // Spotlight use.
            //
            // `.team` resolves to the Lineup tab, which is where the only event
            // the app actually sends (`lineup_finalized`) belongs. Routing is
            // keyed on the team rather than the event type deliberately: any
            // team-scoped event wants the team in front first, and a payload
            // with no usable teamID simply opens the app as before.
            //
            // Freshness is not a concern here even though `AppRouter.Request`
            // discards a stale route on a first-ever drain: `createdAt` is
            // stamped when the request is made, which is this tap, not when the
            // push was sent. A notification opened an hour later is a
            // deliberate request and reads as one.
            //
            // `applyRoute` ignores a team the device no longer holds, so a push
            // for a team since left or unshared cannot select a phantom.
            if let teamID {
                AppRouter.shared.route(to: .team(teamID))
            }
        }
        completionHandler()
    }

    // MARK: - Permission

    /// Requests notification permission once per install, then registers
    /// for remote notifications so APNs can deliver push alerts.
    func requestPermissionIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: permissionKey) else {
            // Already asked — still register in case the token refreshed.
            DeviceTokenManager.shared.registerForRemoteNotifications()
            return
        }
        UserDefaults.standard.set(true, forKey: permissionKey)

        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                Log.push.info("Notification permission granted: \(granted, privacy: .public)")
                if granted {
                    await MainActor.run {
                        DeviceTokenManager.shared.registerForRemoteNotifications()
                    }
                }
            } catch {
                Log.push.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Worker POST

    /// Sends a notification trigger to the Cloudflare Worker.
    /// Fire-and-forget — the Worker handles delivery to all other coaches.
    ///
    /// - Parameters:
    ///   - eventType: One of the supported event types (see Worker's buildPayload)
    ///   - team: The active team (provides teamID, teamName, coachName)
    ///   - metadata: Optional extra context (opponent, gameDate, etc.)
    func postEvent(
        eventType: String,
        team: Team,
        metadata: [String: String] = [:]
    ) {
        var fullMetadata = metadata
        fullMetadata["teamName"] = team.name

        // triggeredBy is the display name the notification body reads back
        // ("<name> finalized the lineup"). triggeredByToken is what the Worker
        // excludes on, and the two are deliberately different things: coachName
        // is UIDevice.current.name, which iOS 16 reduced to "iPhone" on every
        // device, so using it as an identity matched every token and delivered
        // nothing. Omitted rather than sent empty when APNs hasn't answered yet
        // — the Worker treats absence as "legacy client" and falls back to the
        // name comparison, where an empty string would match no one and notify
        // the sender of their own action. See backlog 1.11.
        var payload: [String: Any] = [
            "teamID":      team.id.uuidString,
            "eventType":   eventType,
            "triggeredBy": team.coachName,
            "metadata":    fullMetadata,
        ]
        if let tokenHex = DeviceTokenManager.shared.currentTokenHex {
            payload["triggeredByToken"] = tokenHex
        }

        guard let url = URL(string: workerURL),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            Log.push.error("Invalid Worker URL or payload; event not sent")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    Log.push.info("Worker responded \(http.statusCode, privacy: .public) for \(eventType, privacy: .public)")
                    Analytics.signal("push.sent", parameters: [
                        "eventType": eventType,
                        "status": "\(http.statusCode)"
                    ])
                }
            } catch {
                Log.push.error("Worker POST failed: \(error.localizedDescription, privacy: .public)")
                Analytics.signal("push.sent", parameters: [
                    "eventType": eventType,
                    "status": "network_error"
                ])
            }
        }
    }
}

// MARK: - Event Type Constants

extension NotificationManager {
    static let eventLineupFinalized = "lineup_finalized"
    static let eventGameArchived    = "game_archived"
    static let eventArchivePrompt   = "archive_prompt"
    static let eventTeamInvite      = "team_invite"
    static let eventTip             = "tip"
}
