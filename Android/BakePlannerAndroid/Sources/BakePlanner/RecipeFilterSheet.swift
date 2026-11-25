import BakePlannerCore
import SwiftUI

/// The recipe list's filter: one choice per facet (duration, day flow,
/// leavening, grain, dough yield, equipment, history), "Wenig Arbeit", the
/// pantry switches, "Fertig bis", and the person's saved collections — the
/// iPhone's filter menu as a sheet, since SkipUI menus hold no pickers.
struct RecipeFilterSheet: View {
    let model: AppModel
    /// The saved collection whose name is being changed, if any.
    @State var renaming: SavedRecipeCollection?
    @State var renameName = ""
    @State var newName = ""
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    init(model: AppModel, renaming: SavedRecipeCollection? = nil) {
        self.model = model
        _renaming = State(initialValue: renaming)
        _renameName = State(initialValue: renaming?.name ?? "")
    }

    private var filter: RecipeFacetFilter { model.facetFilter }

    var body: some View {
        Form {
            Section {
                durationRow
                dayFlowRow
                leaveningRow
                grainRow
                doughYieldRow
                equipmentRow
                historyRow
                Toggle("Wenig Arbeit", isOn: Binding(
                    get: { model.facetFilter.lowWorkOnly },
                    set: { model.facetFilter.lowWorkOnly = $0 }
                ))
                if !model.pantryItems.isEmpty {
                    Toggle("Aus dem Vorrat", isOn: Binding(
                        get: { model.facetFilter.pantryOnly },
                        set: { model.facetFilter.pantryOnly = $0 }
                    ))
                    Toggle("Vorrat aufbrauchen", isOn: Binding(
                        get: { model.facetFilter.useUpOnly },
                        set: { model.facetFilter.useUpOnly = $0 }
                    ))
                }
            } header: {
                Text("Facetten")
            }

            Section {
                Toggle("Fertig bis", isOn: Binding(
                    get: { model.finishBy != nil },
                    set: { model.finishBy = $0 ? FinishByPlanner.morningFinish(after: Date()) : nil }
                ))
                if let finishBy = model.finishBy {
                    DatePicker("Fertig bis", selection: Binding(
                        get: { finishBy },
                        set: { model.finishBy = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                }
            } footer: {
                Text("Die Liste zeigt nur Rezepte, die bis dahin fertig werden, und bei jedem, wann Du anfangen musst. Vorheizzeit, Tagesbeginn und Tagesende kommen aus den Einstellungen.")
            }

            if filter.isActive || model.finishBy != nil {
                Section {
                    Button("Filter zurücksetzen", role: .destructive) {
                        model.facetFilter = RecipeFacetFilter()
                        model.finishBy = nil
                    }
                }
            }

            if filter.isActive && model.savedCollection(matching: filter) == nil {
                Section {
                    TextField("Name der Sammlung", text: $newName)
                    Button("Sichern") {
                        if model.saveCollection(named: newName) {
                            newName = ""
                        }
                    }
                    .disabled(SavedRecipeCollection.cleanName(newName) == nil)
                } header: {
                    Text("Sammlung sichern")
                } footer: {
                    Text("Die gesetzten Facetten erscheinen unter diesem Namen als Chip über der Liste.")
                }
            }

            if let renaming {
                Section {
                    TextField("Name der Sammlung", text: $renameName)
                    Button("Sichern") {
                        model.renameCollection(renaming.id, to: renameName)
                        self.renaming = nil
                    }
                    .disabled(SavedRecipeCollection.cleanName(renameName) == nil)
                    Button("Abbrechen") {
                        self.renaming = nil
                    }
                } header: {
                    Text("Sammlung umbenennen")
                }
            }

            if !model.savedCollections.isEmpty {
                Section {
                    ForEach(model.savedCollections, id: \.id) { saved in
                        Button {
                            renaming = saved
                            renameName = saved.name
                        } label: {
                            HStack {
                                Text(verbatim: saved.name)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if model.facetFilter == saved.filter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.accent(colorScheme))
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.removeCollection(model.savedCollections[index].id)
                        }
                    }
                } header: {
                    Text("Gesicherte Sammlungen")
                } footer: {
                    Text("Tippe auf eine Sammlung, um sie umzubenennen; Wischen löscht sie.")
                }
            }
        }
        .navigationTitle("Filter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
    }

    // MARK: Facet rows — a menu each, the current choice on the right

    private func facetRow<Content: View>(_ title: LocalizedStringKey, value: LocalizedStringKey,
                                         @ViewBuilder options: () -> Content) -> some View {
        Menu {
            options()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(Palette.accentText(colorScheme))
            }
        }
    }

    private var durationRow: some View {
        facetRow("Dauer", value: RecipeFacetText.duration(filter.duration)) {
            Button("Alle") { model.facetFilter.duration = nil }
            Button("Unter 4 Stunden") { model.facetFilter.duration = .short }
            Button("4 bis 12 Stunden") { model.facetFilter.duration = .halfDay }
            Button("Über Nacht") { model.facetFilter.duration = .overnight }
            Button("Mehrtägig") { model.facetFilter.duration = .multiDay }
        }
    }

    private var dayFlowRow: some View {
        facetRow("Tagesablauf", value: RecipeFacetText.dayFlow(filter.dayFlow)) {
            Button("Alle") { model.facetFilter.dayFlow = nil }
            Button("Abends ansetzen, morgens backen") { model.facetFilter.dayFlow = .eveningToMorning }
            Button("Morgens ansetzen, abends backen") { model.facetFilter.dayFlow = .sameDay }
            Button("Fertig in 2 Stunden") { model.facetFilter.dayFlow = .quick }
        }
    }

    private var leaveningRow: some View {
        facetRow("Triebmittel", value: RecipeFacetText.leavening(filter.leavening)) {
            Button("Alle") { model.facetFilter.leavening = nil }
            Button("Reiner Sauerteig") { model.facetFilter.leavening = .sourdough }
            Button("Lievito Madre") { model.facetFilter.leavening = .lievitoMadre }
            Button("Hefe") { model.facetFilter.leavening = .yeast }
            Button("Sauerteig und Hefe") { model.facetFilter.leavening = .mixed }
        }
    }

    private var grainRow: some View {
        facetRow("Mehl", value: RecipeFacetText.grain(filter.grain)) {
            Button("Alle") { model.facetFilter.grain = nil }
            Button("Überwiegend Weizen") { model.facetFilter.grain = .wheat }
            Button("Überwiegend Roggen") { model.facetFilter.grain = .rye }
            Button("Überwiegend Dinkel") { model.facetFilter.grain = .spelt }
            Button("Überwiegend Vollkorn") { model.facetFilter.grain = .wholeGrain }
        }
    }

    private var doughYieldRow: some View {
        facetRow("Teigausbeute", value: RecipeFacetText.doughYield(filter.doughYield)) {
            Button("Alle") { model.facetFilter.doughYield = nil }
            Button("Fest, unter TA 165") { model.facetFilter.doughYield = .firm }
            Button("Mittel, TA 165 bis 180") { model.facetFilter.doughYield = .medium }
            Button("Weich, ab TA 180") { model.facetFilter.doughYield = .soft }
        }
    }

    private var equipmentRow: some View {
        facetRow("Ausstattung", value: RecipeFacetText.equipment(filter.equipment)) {
            Button("Alle") { model.facetFilter.equipment = nil }
            Button("Backstein") { model.facetFilter.equipment = .bakingStone }
            Button("Kastenform") { model.facetFilter.equipment = .loafTin }
            Button("Gärkörbchen") { model.facetFilter.equipment = .proofingBasket }
            Button("Topf") { model.facetFilter.equipment = .dutchOven }
        }
    }

    private var historyRow: some View {
        facetRow("Backhistorie", value: RecipeFacetText.history(filter.history)) {
            Button("Alle") { model.facetFilter.history = nil }
            Button("Nie gebacken") { model.facetFilter.history = .never }
            Button("Lange nicht gebacken") { model.facetFilter.history = .longAgo }
            Button("Lieblinge") { model.facetFilter.history = .favourites }
        }
    }
}

/// How the facets and the preset collections read; the same texts as on
/// the iPhone.
enum RecipeFacetText {
    static func duration(_ value: RecipeFacets.Duration?) -> LocalizedStringKey {
        switch value {
        case nil: return "Alle"
        case .short: return "Unter 4 Stunden"
        case .halfDay: return "4 bis 12 Stunden"
        case .overnight: return "Über Nacht"
        case .multiDay: return "Mehrtägig"
        }
    }

    static func dayFlow(_ value: RecipeFacets.DayFlow?) -> LocalizedStringKey {
        switch value {
        case nil: return "Alle"
        case .eveningToMorning: return "Abends ansetzen, morgens backen"
        case .sameDay: return "Morgens ansetzen, abends backen"
        case .quick: return "Fertig in 2 Stunden"
        }
    }

    static func leavening(_ value: RecipeFacets.Leavening?) -> LocalizedStringKey {
        switch value {
        // `.none` is a recipe without a leavening agent, which the menu does
        // not offer; it reads like no choice.
        case nil, .some(.none): return "Alle"
        case .sourdough: return "Reiner Sauerteig"
        case .lievitoMadre: return "Lievito Madre"
        case .yeast: return "Hefe"
        case .mixed: return "Sauerteig und Hefe"
        }
    }

    static func grain(_ value: RecipeFacetFilter.Grain?) -> LocalizedStringKey {
        switch value {
        case nil: return "Alle"
        case .wheat: return "Überwiegend Weizen"
        case .rye: return "Überwiegend Roggen"
        case .spelt: return "Überwiegend Dinkel"
        case .wholeGrain: return "Überwiegend Vollkorn"
        }
    }

    static func doughYield(_ value: RecipeFacets.DoughYieldBand?) -> LocalizedStringKey {
        switch value {
        case nil: return "Alle"
        case .firm: return "Fest, unter TA 165"
        case .medium: return "Mittel, TA 165 bis 180"
        case .soft: return "Weich, ab TA 180"
        }
    }

    static func equipment(_ value: RecipeFacets.Equipment?) -> LocalizedStringKey {
        switch value {
        case nil: return "Alle"
        case .bakingStone: return "Backstein"
        case .loafTin: return "Kastenform"
        case .proofingBasket: return "Gärkörbchen"
        case .dutchOven: return "Topf"
        }
    }

    static func history(_ value: RecipeFacetFilter.HistoryChoice?) -> LocalizedStringKey {
        switch value {
        case nil: return "Alle"
        case .never: return "Nie gebacken"
        case .longAgo: return "Lange nicht gebacken"
        case .favourites: return "Lieblinge"
        }
    }

    static func collection(_ collection: RecipeCollection) -> LocalizedStringKey {
        switch collection {
        case .morning: return "Für morgen früh"
        case .quick: return "Schnelles Brot"
        case .sourdough: return "Reiner Sauerteig"
        case .longAgo: return "Lange nicht gebacken"
        case .favourites: return "Lieblinge"
        case .pantry: return "Aus dem Vorrat"
        case .useUp: return "Vorrat aufbrauchen"
        }
    }

    /// "heute 07:30", "morgen 07:30", "Sa., 15.11., 12:00".
    static func finish(_ date: Date) -> String {
        let time = PlanText.time(date)
        if Calendar.current.isDateInToday(date) {
            return String(localized: "heute", bundle: .module) + " " + time
        }
        if Calendar.current.isDateInTomorrow(date) {
            return String(localized: "morgen", bundle: .module) + " " + time
        }
        return PlanText.dateTime(date)
    }
}
