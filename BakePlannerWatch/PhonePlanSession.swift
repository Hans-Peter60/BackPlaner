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
//  if the iPhone is out of reach right now. Whenever this app opens or the
//  iPhone comes within reach, it asks the iPhone for the plan as it stands,
//  so a context that was missed does not leave the watch behind.
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
        if let demo = WatchDemoPlan.snapshot() {
            // The App Store screenshots: a fixed plan, no iPhone asked.
            snapshot = demo
            return
        }
        if let cached = Self.loadCache() {
            snapshot = cached
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var steps: [PlanSnapshot.Step] { snapshot.steps }

    /// The step to open on: the one due within the last hour, else the next
    /// one ahead, else the last of the plan — the iPhone's rule. The demo
    /// plan opens on the step the screenshot asks for.
    func currentStepID(at now: Date) -> String? {
        if let index = WatchDemoPlan.requestedStepIndex, snapshot.steps.indices.contains(index) {
            return snapshot.steps[index].id
        }
        return snapshot.currentStep(at: now)?.step.id ?? snapshot.steps.last?.id
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

    /// Asks the iPhone for its plan as it stands — when this app opens and
    /// when the iPhone comes within reach. Within reach the iPhone answers
    /// with the plan directly; the application context follows anyway.
    func requestPlan() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([Self.requestKey: true], replyHandler: { [weak self] reply in
            let planData = reply[Self.planKey] as? Data
            Task { @MainActor in self?.apply(planData: planData) }
        }, errorHandler: nil)
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
            // And the plan as the iPhone has it now, in case the context
            // kept here is older than the plan over there.
            self.requestPlan()
        }
    }

    /// The iPhone came within reach: ask for the plan as it stands.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.requestPlan() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let planData = applicationContext[Self.planKey] as? Data
        Task { @MainActor in self.apply(planData: planData) }
    }
}

/// The plan the App Store screenshots show, in the watch's language. Only
/// with the launch argument `-UITestingWatchDemo`; `-UITestingWatchDemoStep
/// <n>` opens on step n (from 0). The times run from the launch, so the
/// pages read "in 17 Min." and "in 3 Std., 30 Min." whenever they are taken.
enum WatchDemoPlan {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestingWatchDemo")
    }

    static var requestedStepIndex: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard isActive, let flag = arguments.firstIndex(of: "-UITestingWatchDemoStep"),
              flag + 1 < arguments.count else { return nil }
        return Int(arguments[flag + 1])
    }

    static func snapshot(now: Date = Date()) -> PlanSnapshot? {
        guard isActive else { return nil }
        let recipe = String(localized: "Kartoffelbrot mit Saaten")
        func step(_ id: String, _ instruction: String, minutes: Int, duration: Int,
                  component: String? = nil, lines: [String]? = nil) -> PlanSnapshot.Step {
            PlanSnapshot.Step(id: id, recipeName: recipe, instruction: instruction,
                              date: now.addingTimeInterval(TimeInterval(minutes * 60)), duration: duration,
                              componentName: component, ingredientLines: lines)
        }
        let steps = [
            step("demo-1", String(localized: "Hauptteig kneten"), minutes: 17, duration: 10,
                 component: String(localized: "Hauptteig"),
                 lines: [String(localized: "• 800 g Weizenmehl 550"), String(localized: "• 450 g Wasser"),
                         String(localized: "• 200 g Sauerteig"), String(localized: "• 18 g Salz")]),
            step("demo-2", String(localized: "Teig dehnen und falten"), minutes: 47, duration: 5),
            step("demo-3", String(localized: "Laib formen und ins Gärkörbchen legen"), minutes: 135, duration: 15),
            step("demo-4", String(localized: "Backofen anstellen (250 °C)"), minutes: 195, duration: 45),
            step("demo-5", String(localized: "Bei 250 °C fallend auf 220 °C backen"), minutes: 240, duration: 50),
        ]
        return PlanSnapshot(steps: steps, generatedAt: now)
    }
}
