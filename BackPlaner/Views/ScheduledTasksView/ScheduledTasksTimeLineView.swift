//
//  ScheduledTasksTimeLineView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 26.01.22.
//

import SwiftUI
import CoreData

struct ScheduledTasksTimeLineView: View {
    
    @Environment(\.managedObjectContext) private var managedObjectContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    let date = Date() - 60
    
    var nextStepsRequest: FetchRequest<NextStep>
    var nextSteps: FetchedResults<NextStep> { nextStepsRequest.wrappedValue }
    var timeCalculation:TimeCalculation  = TimeCalculation()

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass)   private var vSize

    init() {
        self.nextStepsRequest = FetchRequest(entity: NextStep.entity(), sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
        
        dateFormatter = DateFormatter()
        // the format of the dates on the timeline
        dateFormatter.dateFormat   = "EEE dd\nhh:mm"
    }
    
    // change these to visually style the timeline
    private static let lineWidth:   CGFloat = 2
    private static let dotDiameter: CGFloat = 8
    
    private let dateFormatter: DateFormatter

    /// The stacked date/time stamp for the timeline. On iPhone portrait the time
    /// is shown above the date; otherwise the date stays above the time as before.
    private func stampText(for date: Date) -> String {
        let portrait = hSize == .compact && vSize == .regular
        dateFormatter.dateFormat = portrait ? "hh:mm\nEEE dd" : "EEE dd\nhh:mm"
        return dateFormatter.string(from: date)
    }

    var body: some View {
        
        Group {
//            Text("Geplante nächste Schritte")
//                .font(Theme.brandFont(20))
            
            if nextSteps.isEmpty {
                ContentUnavailableView(
                    "Keine geplanten Schritte",
                    systemImage: "calendar",
                    description: Text("Setze einen Reminder in der Backanleitung eines Rezepts.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {

                List(Array(nextSteps.enumerated()), id: \.element.objectID) { index, item in
                rowAt(index, item: item)
                // removes spacing between the rows
                    .listRowInsets(EdgeInsets())
                // hides separators on SwiftUI 3, for other versions
                // check out https://swiftuirecipes.com/blog/remove-list-separator-in-swiftui
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .clearScrollBackground()
            }
        }
        .warmBackground()
        .navigationTitle("Geplante nächste Schritte")
    }
    
    @ViewBuilder private func rowAt(_ index: Int, item: NextStep) -> some View {
        let calendar           = Calendar.current
        let date               = item.date
        let hasPrevious        = index > 0
        let hasNext            = index < nextSteps.count - 1
        let isPreviousSameDate = hasPrevious && calendar.isDate(date, inSameDayAs: nextSteps[index - 1].date)
        
        HStack {
            ZStack {
                Color.clear // effectively centers the text
                if !isPreviousSameDate {
                    Text(stampText(for: date))
                        .font(Theme.brandFont(13))
                        .multilineTextAlignment(.center)
                }
                else {
                    Text(timeCalculation.calculateTime(t: date))
                        .font(Theme.bodyFont(13))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 48)
            
            GeometryReader { geo in
                ZStack {
                    Color.clear
                    line(height: geo.size.height,
                         hasPrevious: hasPrevious,
                         hasNext: hasNext,
                         isPreviousSameDate: isPreviousSameDate)
                }
            }
            .frame(width: 10)

            Group {
                if let dataImage = fetchRecipeImage(name: item.recipeName) {
                    let image = UIImage(data: dataImage) ?? UIImage()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 30, height: 30, alignment: .center)
            .clipped()
            .cornerRadius(5)
            // Decorative: the recipe name is right next to it.
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.recipeName)
                    .font(Theme.brandFont(15))
                    .foregroundColor(Theme.cardTitle)

                Text(item.instruction)
                    .font(Theme.bodyFont(15))
            }
            // Recipe and step describe one entry on the timeline.
            .accessibilityElement(children: .combine)
        }
    }

    func fetchRecipeImage(name: String) -> Data? {

        let recipes = fetchRecipes(name: name)

        if recipes.count > 0 {

            return recipes[0].image
        }
        else {
            return nil
        }
    }

    func fetchRecipes(name: String) -> [Recipe] {

        return recipes.filter { r in
            return r.name.contains(name)
        }
    }
    
    // this methods implements the rules for showing dots in the
    // timeline, which might differ based on requirements
    @ViewBuilder private func line(height: CGFloat,
                                   hasPrevious: Bool,
                                   hasNext: Bool,
                                   isPreviousSameDate: Bool) -> some View {
        let lineView = Rectangle()
            .foregroundColor(Theme.subtitle)
            .frame(width: ScheduledTasksTimeLineView.lineWidth)
        let dot = Circle()
            // accentText: this line sits on the warm background, so it has to
            // stay light in dark mode rather than following the gradient accent.
            .fill(Theme.accentText)
            .frame(width: ScheduledTasksTimeLineView.dotDiameter,
                   height: ScheduledTasksTimeLineView.dotDiameter)
        let halfHeight    = height / 2
        let quarterHeight = halfHeight / 2
        
        if isPreviousSameDate && hasNext {
            lineView
        } else if hasPrevious && hasNext {
            lineView
            dot
        } else if hasNext {
            lineView
                .frame(height: halfHeight)
                .offset(y: quarterHeight)
            dot
        } else if hasPrevious {
            lineView
                .frame(height: halfHeight)
                .offset(y: -quarterHeight)
            dot
        } else {
            dot
        }
    }
}
