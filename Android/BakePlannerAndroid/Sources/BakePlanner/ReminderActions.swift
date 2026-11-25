import BakePlannerCore
import Foundation

/// What the buttons on a reminder notification do — the iPhone's
/// NotificationActions: "Erledigt" removes the step, "Verschieben um …"
/// moves it, alone or with the plan's later steps. Works on the model the
/// app shows when it is running, so the timeline follows at once; without
/// a running app on a model of its own.
@MainActor
enum ReminderActions {
    static func perform(identifier: String, action: String, minutes: Int, includeFollowing: Bool) async {
        guard let stepID = PlanReminder.stepID(of: identifier) else { return }
        let model: AppModel
        if let current = AppModel.current {
            model = current
        } else {
            model = AppModel()
            model.load()
        }
        model.loadScheduledSteps()
        guard let step = model.scheduledSteps.first(where: { $0.data.id == stepID }) else {
            logger.info("reminder action for a step that is gone: \(identifier)")
            return
        }
        switch action {
        case "done":
            model.markDone(step)
        case "postpone" where minutes > 0:
            _ = await model.shift(step, byMinutes: min(minutes, 1_440), includeFollowing: includeFollowing)
        default:
            break
        }
    }
}
