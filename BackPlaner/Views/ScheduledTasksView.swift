//
//  ScheduledTasksView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 03.12.21.
//

import SwiftUI

struct ScheduledTasksView: View {
    
    @Environment(\.managedObjectContext) private var managedObjectContext
    
    let date = Date() - 60
    
    var nextStepsRequest: FetchRequest<NextSteps>
    var nextSteps: FetchedResults<NextSteps> { nextStepsRequest.wrappedValue }
    @State private var name = ""
    
    init() {
        self.nextStepsRequest = FetchRequest(entity: NextSteps.entity(), sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)]) //, predicate: NSPredicate(format: "date >= %@", date))
    }
    
    var gridItemLayout = [GridItem(.fixed(120), alignment: .leading), GridItem(.fixed(90), alignment: .center), GridItem(.flexible(minimum: 180), alignment: .leading), GridItem(.fixed(80), alignment: .trailing), GridItem(.fixed(120), alignment: .trailing)]
    
    var dateCalculation:DateCalculation = DateCalculation()
        
    var body: some View {
        
        Text("Liste der nächsten Schritte")
            .bold()
        
        ScrollView {
            
            LazyVGrid(columns: gridItemLayout, spacing: 6) {
                
                Text("Beginn").bold()
                Text("Schritt").bold()
                Text("Beschreibung").bold()
                Text("Dauer").bold()
                Text("")
                
                if nextSteps.count > 0 {
                    Group {
                        Text("")
                        Text("")
                        Text(nextSteps[0].recipeName)
                            .font(Font.custom("Avenir Heavy", size: 16))
                        Text("")
                        Text("")
                    }
                }

                ForEach(nextSteps.indices) { i in
                    
                    if nextSteps[i].date > Date() - 60 {
                        
                        if i > 0 && i < nextSteps.count - 1 {
                            
                            if nextSteps[i].recipeName != nextSteps[i - 1].recipeName {
                                
                                Group {
                                    
                                    Text("")
                                    Text("")
                                    Text(nextSteps[i].recipeName)
                                        .font(Font.custom("Avenir Heavy", size: 14))
                                    Text("")
                                    Text("")
                                }
                            }
                        }

                        let step = Rational.decimalPlace(nextSteps[i].step, 10)
                        
                        Text(dateCalculation.calculateDateTime(dT: nextSteps[i].date))
                            .font(Font.custom("Avenir Heavy", size: 16))
                        Text(step)
                            .font(Font.custom("Avenir", size: 14))
                        Text(nextSteps[i].instruction)
                            .font(Font.custom("Avenir", size: 14))
                        Text(Rational.displayHoursMinutes(nextSteps[i].duration))
                            .font(Font.custom("Avenir", size: 14))
                        
                        Button("Erledigt") {

                            managedObjectContext.delete(nextSteps[i])

                            do {
                                try managedObjectContext.save()
                            } catch {
                                // handle the Core Data error
                            }
                        }
                        .font(Font.custom("Avenir", size: 15))
                        .padding(.trailing)
                        .foregroundColor(.gray)
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .onAppear(perform: { self.name = "" } )
    }
}
