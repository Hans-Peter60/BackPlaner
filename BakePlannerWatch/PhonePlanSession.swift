//
//  PhonePlanSession.swift
//  BakePlannerWatch
//
//  The plan as the iPhone last sent it, and the way back for "Erledigt".
//  The iPhone puts its plan snapshot into the Watch Connectivity application
//  context (WatchPlanSync in the app); the system keeps the latest and hands
//  it over as soon as the watch is within reach. A copy stays in the watch's
//  own container, so the plan is there at launch even before the iPhone
//  answers. A step marked done here leaves the copy at once and travels to
//  the iPhone as a queued user-info transfer, which the system delivers even
//  if the iPhone is out of reach right now.
//

import BakePlannerCore
import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class PhonePlanSession: NSObject, WCSessionDelegate {

    private(set) var snapshot: PlanSnapshot = .empty

    /// Steps marked done here that the iPhone has not confirmed yet. A plan
    /// that still carries one of them was made before the iPhone heard of
    /// it, so the step is left out rather than shown again.
    private var locallyDone: [String: Date] = [:]
    private static let doneMemory: TimeInterval = 30 * 60

    /// The keys WatchPlanSync in the app uses.
    private static let planKey = "plan"
    private static let doneKey = "done"
    private static let requestKey = "request"

    override init() {
        super.init()
        if let cached = Self.loadCache() {
            snapshot = cached
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var steps: [PlanSnapshot.Step] { snapshot.steps }

    /// The step to open on: the one due within the last hour, else the next
    /// one ahead, else the last of the plan — the iPhone's rule.
    func currentStepID(at now: Date) -> String? {
        snapshot.currentStep(at: now)?.step.id ?? snapshot.steps.last?.id
    }

    /// Takes the step out of the plan here and tells the iPhone: at once
    /// while it is within reach, so the reminder goes before it fires;
    /// otherwise as a queued transfer the system delivers later.
    func markDone(_ stepID: String) {
        locallyDone[stepID] = Date()
        snapshot = snapshot.removingStep(id: stepID)
        Self.saveCache(snapshot)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload = [Self.doneKey: stepID]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func apply(planData: Data?) {
        guard let planData else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var received = try? decoder.decode(PlanSnapshot.self, from: planData) else { return }

        let now = Date()
        locallyDone = locallyDone.filter { now.timeIntervalSince($0.value) < Self.doneMemory }
        received.steps.removeAll { locallyDone[$0.id] != nil }

        snapshot = received
        Self.saveCache(received)
    }

    // MARK: The copy on the watch

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("plan-snapshot.json")
    }

    private static func loadCache() -> PlanSnapshot? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PlanSnapshot.self, from: data)
    }

    private static func saveCache(_ snapshot: PlanSnapshot) {
        guard let url = cacheURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: WCSessionDelegate — called off the main actor

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard activationState == .activated else { return }
        // The context the iPhone sent last, kept by the system across launches.
        let planData = session.receivedApplicationContext[Self.planKey] as? Data
        Task { @MainActor in
            self.apply(planData: planData)
            // Nothing kept yet: ask the iPhone, in case its last send came
            // before this app was installed.
            if planData == nil, session.isReachable {
                session.sendMessage([Self.requestKey: true], replyHandler: nil)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let planData = applicationContext[Self.planKey] as? Data
        Task { @MainActor in self.apply(planData: planData) }
    }
}
