//
//  WatchPlanSync.swift
//  BackPlaner
//
//  The plan on the wrist. The Watch app shows the same snapshot as the
//  widget; it gets it over Watch Connectivity as the application context,
//  which the system keeps and delivers whenever the watch is next within
//  reach. "Erledigt" on the watch comes back as a queued user-info transfer
//  and goes through the same note as the widget's button
//  (PendingWidgetActions), so the step leaves the plan, reminder included,
//  with the next refresh.
//

import BakePlannerCore
import Foundation
import WatchConnectivity

final class WatchPlanSync: NSObject, WCSessionDelegate {

    static let shared = WatchPlanSync()

    /// Keys of the application context (iPhone → Watch) and of the user
    /// info transfers (Watch → iPhone). The Watch app spells them the same.
    static let planKey = "plan"
    static let doneKey = "done"
    static let requestKey = "request"

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// Activates the session. On a Mac or an iPad there is no session at all.
    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Hands the snapshot to the watch. Only the latest plan matters, which
    /// is what the application context is for: the system keeps one and
    /// replaces it with the next.
    func send(_ snapshot: PlanSnapshot) {
        guard let session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled
        else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try session.updateApplicationContext([Self.planKey: try encoder.encode(snapshot)])
        } catch {
            AppLog.notifications.debug("Plan not sent to the watch: \(error.localizedDescription)")
        }
    }

    private func sendCurrent() {
        if let snapshot = PlanSnapshot.load() {
            send(snapshot)
        }
    }

    private func handle(_ userInfo: [String: Any]) {
        if let stepID = userInfo[Self.doneKey] as? String {
            try? PendingWidgetActions.appendDone(stepID: stepID)
            PlanSnapshotPublisher.shared.refresh()
        } else if userInfo[Self.requestKey] != nil {
            sendCurrent()
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            sendCurrent()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) { }

    /// After the user switched to another watch; the new one needs a session.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch app was installed, or a watch paired: send the plan.
    func sessionWatchStateDidChange(_ session: WCSession) {
        sendCurrent()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message)
        replyHandler([:])
    }
}
