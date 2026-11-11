//
//  PlanActionBar.swift
//  BackPlaner
//
//  The glass bar at the foot of the planned steps, the same under the list
//  and under the timeline: the kitchen view of the plan (bake mode), the
//  delete button and the share menu with the Backtag-Zettel and the
//  calendar export. One container, so the shapes are rendered together and
//  blend when they come close.
//

import BakePlannerCore
import SwiftUI

struct PlanActionBar: View {

    /// The plan the screen is narrowed down to; `nil` for every plan. With a
    /// filter the dialogs offer that plan alone besides "all".
    let planFilter: PlanKey?
    /// Every planned step on screen, all plans; the filter is applied here.
    let steps: [NextStep]
    /// The component a step mixes, for the Backtag-Zettel.
    let ingredients: (NextStep) -> (name: String, lines: [String])?
    /// "scheduled" or "timeline": the identifiers the UI tests look for.
    let identifierPrefix: String
    let onBakeMode: () -> Void
    /// Deletes the plan's steps — every plan for `nil`.
    let onDelete: (PlanKey?) -> Void

    @State private var confirmationShown = false
    // "In Kalender eintragen": the choice of plan, the count afterwards, or
    // the refusal.
    @State private var calendarChoiceShown = false
    @State private var calendarEntryCount = 0
    @State private var showingCalendarResult = false
    @State private var showingCalendarDenied = false

    private var visibleSteps: [NextStep] {
        guard let planFilter else { return steps }
        return steps.filter { $0.planKey == planFilter }
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onBakeMode) {
                    Label("Backmodus starten", systemImage: "oven.fill")
                        .font(Theme.brandFont(16))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accentTop)
                .accessibilityIdentifier("\(identifierPrefix).bakeMode")

                Button {
                    confirmationShown = true
                } label: {
                    Image(systemName: "trash")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Geplante Schritte löschen")
                .accessibilityIdentifier("\(identifierPrefix).delete")
                .confirmationDialog("Geplante Schritte löschen?", isPresented: $confirmationShown, titleVisibility: .visible) {
                    // With an active filter the user can restrict the deletion to
                    // the selected recipe instead of clearing the whole plan.
                    if let planFilter {
                        Button("Nur „\(planFilter.recipeName)“ löschen", role: .destructive) {
                            onDelete(planFilter)
                        }
                    }
                    Button("Alle löschen", role: .destructive) {
                        onDelete(nil)
                    }
                    Button("Abbrechen", role: .cancel) { }
                } message: {
                    if let planFilter {
                        Text("Entferne nur die geplanten Schritte von „\(planFilter.recipeName)“ samt Erinnerungen – oder alle geplanten Schritte.")
                    } else {
                        Text("Dies entfernt alle geplanten Schritte und die zugehörigen Erinnerungen.")
                    }
                }

                // The plan's steps into the calendar, so the household sees
                // when the oven is taken.
                Menu {
                    // The steps day by day as a PDF for the kitchen wall —
                    // a Pro feature like the recipe PDF.
                    ProGate(.pdfExport) {
                        FileShareLink(item: BakeDayPDFExport(sheet: PlannedStepExport.bakeDaySheet(steps: visibleSteps, ingredients: ingredients)),
                                      preview: SharePreview(Text("Backtag-Zettel"), image: Image(systemName: "doc.richtext"))) {
                            Label("Backtag-Zettel teilen", systemImage: "doc.richtext")
                        }
                    } label: {
                        Label("Backtag-Zettel teilen", systemImage: "doc.richtext")
                    }
                    Button {
                        calendarChoiceShown = true
                    } label: {
                        Label("In Kalender eintragen", systemImage: "calendar.badge.plus")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Teilen und eintragen")
                .accessibilityIdentifier("\(identifierPrefix).share")
                .confirmationDialog("In Kalender eintragen?", isPresented: $calendarChoiceShown, titleVisibility: .visible) {
                    if let planFilter {
                        Button("Nur „\(planFilter.recipeName)“ eintragen") {
                            exportToCalendar(plan: planFilter)
                        }
                    }
                    Button("Alle Pläne eintragen") {
                        exportToCalendar(plan: nil)
                    }
                    Button("Abbrechen", role: .cancel) { }
                } message: {
                    Text("Jeder geplante Schritt wird ein Termin in Deinem Standardkalender. Ein erneutes Eintragen legt neue Termine an.")
                }
                .calendarExportAlerts(entryCount: calendarEntryCount,
                                      showingResult: $showingCalendarResult, showingDenied: $showingCalendarDenied)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// The steps of `plan` — every plan for nil — as calendar entries.
    private func exportToCalendar(plan: PlanKey?) {
        let chosen = plan == nil ? steps : steps.filter { $0.planKey == plan }
        Task { @MainActor in
            do {
                let count = try await PlannedStepExport.addToCalendar(chosen)
                guard count > 0 else { return }
                calendarEntryCount = count
                showingCalendarResult = true
            } catch {
                showingCalendarDenied = true
            }
        }
    }
}

extension View {
    /// The two outcomes of "In Kalender eintragen": how many events were
    /// made, or that the calendar may not be written.
    func calendarExportAlerts(entryCount: Int, showingResult: Binding<Bool>, showingDenied: Binding<Bool>) -> some View {
        self
            .alert("In den Kalender eingetragen", isPresented: showingResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\(entryCount) Termine angelegt.")
            }
            .alert("Kein Zugriff auf den Kalender", isPresented: showingDenied) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("BakePlanner darf keine Termine anlegen. Das lässt sich in den iOS-Einstellungen unter BakePlanner ändern.")
            }
    }
}
