//
//  BakeYearbookView.swift
//  BackPlaner
//
//  The sheet behind "Backjahr-Buch" in the bake history: pick the year,
//  put a name on the cover, see what the book will hold, and share the PDF.
//  The book is built when the sheet opens and rebuilt when the year or the
//  name changes; the PDF is rendered only when the share sheet asks.
//

import BakePlannerCore
import CoreData
import SwiftUI

struct BakeYearbookView: View {

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("yearbook.bakerName") private var bakerName = ""

    @State private var years: [Int] = []
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var document: BakeYearbookDocument?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if years.isEmpty {
                        Text("Noch kein abgeschlossenes Backen – das Buch entsteht aus der Backhistorie.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Jahr", selection: $year) {
                            ForEach(years, id: \.self) { year in
                                Text(verbatim: String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField("Name auf dem Titelblatt", text: $bakerName)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Das Buch nimmt alle Backvorgänge des Jahres mit ihren Fotos, die Lieblingsrezepte als Rezeptseiten, die Erkenntnisse aus Deinen Messwerten und das Anstellgut-Tagebuch.")
                }

                if let document, !document.book.isEmpty {
                    Section("Inhalt") {
                        LabeledContent("Brote", value: String(document.book.bakes))
                        LabeledContent("Backtage", value: String(document.book.bakingDays))
                        LabeledContent("Backfotos", value: String(document.photos.count))
                        LabeledContent("Lieblingsrezepte", value: String(document.book.favourites.count))
                        if let starter = document.book.starter {
                            LabeledContent("Fütterungen", value: String(starter.feedings))
                        }
                    }
                    Section {
                        ProGate(.yearbook) {
                            FileShareLink(item: BakeYearbookPDFExport(document: document),
                                          preview: SharePreview(document.title, image: Image(systemName: "book.closed"))) {
                                Label("Backjahr-Buch teilen", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityIdentifier("yearbook.share")
                        } label: {
                            Label("Backjahr-Buch teilen", systemImage: "square.and.arrow.up")
                        }
                    } footer: {
                        Text("Ein PDF im A4-Format – zum Drucken, Binden oder Verschicken.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .warmBackground()
            .navigationTitle("Backjahr-Buch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                years = BakeYearbookDocument.availableYears(in: viewContext)
                if let first = years.first, !years.contains(year) { year = first }
                rebuild()
            }
            .onChange(of: year) { _, _ in rebuild() }
            .onChange(of: bakerName) { _, _ in rebuild() }
        }
    }

    private func rebuild() {
        guard years.contains(year) else {
            document = nil
            return
        }
        document = BakeYearbookDocument.load(year: year, bakerName: bakerName, in: viewContext)
    }
}
