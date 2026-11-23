import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Shopping list into Reminders: add, update, leave alone")
struct RemindersSyncTests {

    private let flourID = "11111111-1111-1111-1111-111111111111"
    private let yeastID = "22222222-2222-2222-2222-222222222222"
    private let saltID = "33333333-3333-3333-3333-333333333333"

    @Test("A first send adds every line with its link")
    func firstSend() {
        let plan = RemindersSync.plan([.init(id: flourID, title: "1 kg Roggenmehl 1150"), .init(id: nil, title: "Eier")],
                                      existing: [])
        #expect(plan.added == 2 && plan.updated == 0 && plan.unchanged == 0)
        #expect(plan.actions.first == .add(title: "1 kg Roggenmehl 1150", url: RemindersSync.marker(for: flourID)))
    }

    @Test("Sending again updates changed lines, keeps ticked ones and skips hand-typed twins")
    func again() {
        let existing = [
            RemindersSync.Existing(identifier: "r1", title: "1 kg Roggenmehl 1150", url: RemindersSync.marker(for: flourID), isCompleted: false),
            RemindersSync.Existing(identifier: "r2", title: "42 g Hefe", url: RemindersSync.marker(for: yeastID), isCompleted: true),
            RemindersSync.Existing(identifier: "r3", title: "Meersalz ", url: nil, isCompleted: false),
        ]
        let plan = RemindersSync.plan([
            .init(id: flourID, title: "2 kg Roggenmehl 1150"),
            .init(id: yeastID, title: "84 g Hefe"),
            .init(id: saltID, title: "meersalz"),
            .init(id: nil, title: "Butter"),
        ], existing: existing)
        #expect(plan.actions == [.update(identifier: "r1", title: "2 kg Roggenmehl 1150"),
                                 .add(title: "Butter", url: nil)])
        #expect(plan.unchanged == 2 && plan.added == 1 && plan.updated == 1)
    }
}
