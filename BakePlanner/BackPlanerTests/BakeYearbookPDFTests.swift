//
//  BakeYearbookPDFTests.swift
//  BackPlanerTests
//
//  The yearbook from an in-memory store: the document gathers the year's
//  bakes, photos and feedings, and the PDF renders with its pages. The PDF
//  is written to the temporary directory so it can be looked at.
//

import BakePlannerCore
import CoreData
import Foundation
import PDFKit
import Testing
import UIKit
@testable import BackPlaner

@Suite("The baking yearbook")
@MainActor
struct BakeYearbookPDFTests {

    private func photo(_ color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240)).jpegData(withCompressionQuality: 0.8) { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        }
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test("The document gathers the year's bakes with photos, flour and the favourites; the PDF has its pages")
    func documentAndPDF() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let recipes = CoreDataRecipeStore(context: context)
        let histories = CoreDataBakeHistoryStore(context: context)
        let feedings = CoreDataStarterFeedingLogStore(context: context)
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        var starterContent = RecipeStoreContract.bread()
        starterContent.name = "Roggensauer"
        let starter = try recipes.add(starterContent, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)

        let year = Calendar.current.component(.year, from: Date()) - 1
        _ = try histories.add(toRecipe: bread.id, date: day(year, 1, 12), comment: "Schöne Kruste", images: [photo(.brown)],
                              facts: BakeHistoryFacts(roomTemperature: 22, finalProofMinutes: 60, flour: "Weizen 550",
                                                      outcome: "offen", rating: 5))
        _ = try histories.add(toRecipe: bread.id, date: day(year, 1, 26), comment: "", images: [],
                              facts: BakeHistoryFacts(roomTemperature: 23, finalProofMinutes: 70, rating: 4))
        _ = try histories.add(toRecipe: bread.id, date: day(year, 6, 3), comment: "Sommer", images: [photo(.orange), photo(.red)],
                              facts: BakeHistoryFacts(outcome: "dicht", rating: 3))
        // The year after: not in this book.
        _ = try histories.add(toRecipe: bread.id, date: day(year + 1, 1, 2), comment: "", images: [], facts: BakeHistoryFacts())
        _ = try feedings.add(toRecipe: starter.id, date: day(year, 1, 10), facts: StarterFeedingFacts(peakMinutes: 480))
        _ = try feedings.add(toRecipe: starter.id, date: day(year, 7, 10), facts: StarterFeedingFacts(peakMinutes: 300))

        let years = BakeYearbookDocument.availableYears(in: context)
        #expect(years.contains(year))

        let document = BakeYearbookDocument.load(year: year, bakerName: " Hans-Peter ", in: context)
        let book = document.book
        #expect(book.bakes == 3)
        #expect(book.bakingDays == 3)
        #expect(book.flourKilograms > 0)
        #expect(book.months.count == 2)
        #expect(book.favourites.first?.name == bread.content.name)
        #expect(book.favourites.first?.count == 3)
        #expect(document.photos.count == 2)
        #expect(book.coverPhotoKey.map { document.photos[$0] != nil } == true)
        #expect(document.recipes[bread.content.name] != nil)
        #expect(document.bakerName == "Hans-Peter")
        #expect(book.starter?.feedings == 2)
        #expect(book.outcomes.map(\.keyword).sorted() == ["dicht", "offen"])

        let data = RecipePDFRenderer.render(document)
        let pdf = try #require(PDFDocument(data: data))
        // Cover, figures, January, June, the favourite's recipe page, lessons, resolutions.
        #expect(pdf.pageCount >= 6)
        #expect(pdf.string?.contains("Hans-Peter") == true)
        #expect(pdf.string?.contains(bread.content.name) == true)

        let url = URL(fileURLWithPath: "/tmp/BakeYearbook-test.pdf")
        try? data.write(to: url)
    }

    @Test("A year without bakes gives an empty book and still renders")
    func emptyYear() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let document = BakeYearbookDocument.load(year: 1999, bakerName: "", in: context)
        #expect(document.book.isEmpty)
        #expect(BakeYearbookDocument.availableYears(in: context).isEmpty)
        let pdf = try #require(PDFDocument(data: RecipePDFRenderer.render(document)))
        #expect(pdf.pageCount >= 3)
    }
}
