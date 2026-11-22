import Foundation
import Testing
@testable import BakePlannerCore

@Suite("CookPlanner: the plan as a timeline")
struct KitchenTimelineLayoutTests {

    private func placement(_ id: String, _ component: String, _ start: Int, _ end: Int) -> KitchenPlacement {
        KitchenPlacement(task: KitchenTask(id: id, name: id, component: component, hands: end - start),
                         start: start, handsEnd: end, end: end)
    }

    @Test("Overlapping steps share their lane side by side, a lone step keeps the width")
    func tracks() {
        let bars = KitchenTimelineLayout.bars(for: [
            placement("sauce", "A", 0, 20), placement("cut", "A", 2, 6), placement("plate", "A", 25, 28),
            placement("herbs", "A", 8, 12),
        ])
        let byID = Dictionary(uniqueKeysWithValues: bars.map { ($0.id, $0) })
        #expect(byID["sauce"]?.track == 0 && byID["sauce"]?.tracks == 2)
        #expect(byID["cut"]?.track == 1 && byID["cut"]?.tracks == 2)
        #expect(byID["herbs"]?.track == 1)
        #expect(byID["plate"]?.track == 0 && byID["plate"]?.tracks == 1)
    }

    @Test("Lanes follow the dish's components, steps without one come last")
    func lanes() throws {
        let tasks = [KitchenTask(id: "a", name: "a", component: "Fisch", hands: 5),
                     KitchenTask(id: "b", name: "b", component: "Sauce", hands: 5),
                     KitchenTask(id: "c", name: "c", hands: 3)]
        let schedule = try KitchenScheduler.schedule(tasks, kitchen: Kitchen(), budget: 30)
        let layout = KitchenTimelineLayout(schedule: schedule, components: ["Sauce", "Fisch"])
        #expect(layout.lanes.map(\.component) == ["Sauce", "Fisch", ""])
        #expect(layout.makespan == schedule.makespan)
        #expect(layout.ticks(every: 5).first == 0 && layout.ticks(every: 5).last == schedule.makespan)
    }
}
