//
//  LastBakeCardView.swift
//  BackPlaner
//
//  "How did it go last time?" — shown in the baking view of an own recipe
//  while it is planned again: the temperatures, proof times, flour, crumb
//  and comment of the last bake that already happened, one tap away from
//  adding what is still missing. The most useful moment for the history is
//  the next plan of the same recipe, not the history list.
//

import SwiftUI
import CoreData

struct LastBakeCardView: View {

    let bakeHistory: BakeHistory
    let recipeName: String

    @Environment(\.managedObjectContext) private var viewContext

    private let dateFormat = DateFormat()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label {
                    Text("Letztes Mal")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundColor(Theme.accentText)

                Spacer(minLength: 8)

                Text(dateFormat.calculateDate(dT: bakeHistory.date))
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
            }

            if bakeHistory.hasNotes {
                let facts = bakeHistory.facts
                let items = facts.items()

                if !items.isEmpty {
                    BakeHistoryFactsRows(items: items)
                }

                if !BakeHistoryFacts.isPlaceholderComment(bakeHistory.comment) {
                    Text(bakeHistory.comment)
                        .font(Theme.bodyFont(15))
                        .foregroundColor(Theme.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if facts.isEmpty {
                    Text("Temperaturen, Gare und Mehl sind noch nicht notiert.")
                        .font(Theme.bodyFont(13))
                        .foregroundColor(Theme.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }

                editLink("Ergänzen")
            } else {
                Text("Noch nichts notiert. Wie lief es – Raum- und Teigtemperatur, Gare, Mehl, Krume?")
                    .font(Theme.bodyFont(15))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)

                editLink("Jetzt eintragen")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func editLink(_ title: LocalizedStringKey) -> some View {
        NavigationLink {
            BakeHistoryUpdateFormView(recipeName: recipeName, bakeHistory: bakeHistory)
                .environment(\.managedObjectContext, viewContext)
        } label: {
            Label(title, systemImage: "square.and.pencil")
                .font(Theme.brandFont(14))
                .foregroundColor(Theme.accentText)
        }
    }
}

// MARK: - Facts as rows

/// The recorded facts as small labelled values: the four numbers two to a
/// row, flour and the crumb words — which can be long — on rows of their own.
struct BakeHistoryFactsRows: View {

    let items: [BakeHistoryFacts.Item]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let numericKinds: Set<BakeHistoryFacts.Kind> = [
        .roomTemperature, .doughTemperature, .bulkProof, .finalProof
    ]

    private var numericItems: [BakeHistoryFacts.Item] {
        items.filter { Self.numericKinds.contains($0.kind) }
    }

    private var textItems: [BakeHistoryFacts.Item] {
        items.filter { !Self.numericKinds.contains($0.kind) }
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), alignment: .leading)]
        }
        return [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !numericItems.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(numericItems) { item in
                        row(item)
                    }
                }
            }
            ForEach(textItems) { item in
                row(item)
            }
        }
    }

    private func row(_ item: BakeHistoryFacts.Item) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: item.kind.systemImage)
                .font(.caption)
                .foregroundColor(Theme.subtitle)
                .frame(width: 16)
                .padding(.top, 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.kind.title)
                    .font(.caption)
                    .foregroundColor(Theme.subtitle)
                Text(verbatim: item.value)
                    .font(Theme.bodyFont(15))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Facts in one line

/// The recorded facts as one running line — "Raum 22 °C · Teig 25 °C ·
/// Stockgare 3h 30m · Weizen 550 · offen" — for a list row or a gallery tile.
/// Nothing when nothing was recorded.
struct BakeHistoryFactsLineView: View {

    let facts: BakeHistoryFacts

    var body: some View {
        let line = facts.summaryLine()
        if !line.isEmpty {
            Text(verbatim: line)
        }
    }
}
