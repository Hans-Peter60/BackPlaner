//
//  CloudDishImport.swift
//  BakePlannerCore
//
//  What the cloud AI answers when it reads a cooking recipe for
//  CookPlanner (Cloud Function analyzeDishSteps), and the dish built from
//  it: every number held to a plausible range, dependencies only
//  backwards so no step waits for itself, the rest filled by the defaults.
//

import Foundation

public struct CloudDishAnalysis: Decodable, Sendable {
    public let dish: CloudDish
    public let model: String
    public let freeImports: CloudRecipeAnalysis.FreeImports?

    public init(dish: CloudDish, model: String, freeImports: CloudRecipeAnalysis.FreeImports? = nil) {
        self.dish = dish
        self.model = model
        self.freeImports = freeImports
    }
}

public struct CloudDish: Decodable, Sendable {
    public var title: String?
    public var servings: Int?
    public var sourceLanguage: String?
    public var components: [String]?
    public var steps: [CloudDishStep]
    public var warnings: [String]?

    public init(title: String? = nil, servings: Int? = nil, sourceLanguage: String? = nil,
                components: [String]? = nil, steps: [CloudDishStep], warnings: [String]? = nil) {
        self.title = title
        self.servings = servings
        self.sourceLanguage = sourceLanguage
        self.components = components
        self.steps = steps
        self.warnings = warnings
    }
}

public struct CloudDishStep: Decodable, Sendable {
    public var text: String?
    public var componentName: String?
    public var handsMinutes: Int?
    public var unattendedMinutes: Int?
    public var unattendedMinMinutes: Int?
    public var unattendedMaxMinutes: Int?
    /// "none", "burner" or "oven".
    public var station: String?
    public var ovenTemperature: Int?
    /// -1 when the result keeps.
    public var maxWaitMinutes: Int?
    /// Indices of the steps this one waits for.
    public var dependsOn: [Int]?

    public init(text: String? = nil, componentName: String? = nil, handsMinutes: Int? = nil,
                unattendedMinutes: Int? = nil, unattendedMinMinutes: Int? = nil, unattendedMaxMinutes: Int? = nil,
                station: String? = nil, ovenTemperature: Int? = nil, maxWaitMinutes: Int? = nil,
                dependsOn: [Int]? = nil) {
        self.text = text
        self.componentName = componentName
        self.handsMinutes = handsMinutes
        self.unattendedMinutes = unattendedMinutes
        self.unattendedMinMinutes = unattendedMinMinutes
        self.unattendedMaxMinutes = unattendedMaxMinutes
        self.station = station
        self.ovenTemperature = ovenTemperature
        self.maxWaitMinutes = maxWaitMinutes
        self.dependsOn = dependsOn
    }
}

public enum CloudDishImport {

    /// The dish as the editor shows it before the cook keeps it. Steps
    /// without text are dropped; a dependency on a later step or on
    /// itself is dropped too, so the plan cannot run in a circle; steps
    /// that name none get the defaults. `fallbackName` is the app's word
    /// for a dish without a title.
    public static func dish(from cloud: CloudDish, source: KitchenDishSource, now: Date = Date(),
                            fallbackName: String = "Gericht") -> KitchenDish {
        let steps = cloud.steps.enumerated().compactMap { index, step -> (Int, CloudDishStep, String)? in
            let text = (step.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (index, step, text)
        }
        // Original index → id, for the dependencies.
        var ids = [Int: String]()
        for (position, entry) in steps.enumerated() { ids[entry.0] = "step-\(position + 1)" }

        let tasks = steps.map { original, step, text -> KitchenTask in
            let id = ids[original] ?? "step-\(original)"
            let hands = Plausible.minutes(step.handsMinutes ?? 0)
            let unattended = Plausible.minutes(step.unattendedMinutes ?? 0)
            var window: ClosedRange<Int>?
            if let low = step.unattendedMinMinutes, let high = step.unattendedMaxMinutes, high > 0, low <= high {
                window = Plausible.minutes(low)...Plausible.minutes(high)
            }
            let station: KitchenStation?
            switch (step.station ?? "").lowercased() {
            case "burner", "herd", "platte": station = .burner
            case "oven", "ofen", "backofen": station = .oven
            default: station = nil
            }
            let temperature = step.ovenTemperature.flatMap { $0 > 0 ? Plausible.temperature(Double($0)).map(Int.init) : nil }
            let maxWait = step.maxWaitMinutes.flatMap { $0 >= 0 ? Plausible.minutes($0) : nil }
            let after = (step.dependsOn ?? []).filter { $0 < original && $0 >= 0 }.compactMap { ids[$0] }
            return KitchenTask(id: id, name: text, component: (step.componentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                               hands: hands, unattended: unattended, station: station, after: after,
                               maxWait: maxWait, window: window, ovenTemperature: temperature)
        }

        let title = (cloud.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let servings = cloud.servings.flatMap { $0 > 0 ? min($0, 99) : nil }
        return KitchenDish(name: title.isEmpty ? fallbackName : title,
                           source: source, servings: servings, createdAt: now,
                           tasks: KitchenDishDefaults.withDependencies(tasks))
    }
}
