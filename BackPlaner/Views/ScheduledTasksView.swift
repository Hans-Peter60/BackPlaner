//
//  ScheduledTasksView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 03.12.21.
//

import SwiftUI

struct ScheduledTasksView: View {
    
    @Environment(\.managedObjectContext) private var managedObjectContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    var nextSteps: FetchedResults<NextSteps>
    
    // Tab selection
    @Binding var tabSelection: Int
    var gridItemLayout = [GridItem(.fixed(110), alignment: .leading), GridItem(.fixed(90), alignment: .center), GridItem(.flexible(minimum: 180), alignment: .leading), GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(120), alignment: .trailing)]
    var dateCalculation:DateCalculation = DateCalculation()
    @State private var name = ""
    
    var body: some View {
        
        Text("Liste der nächsten Schritte")
            .bold()
        
        List {
 
            LazyVGrid(columns: gridItemLayout, spacing: 6) {
                
                Text("Beginn").bold()
                Text("Schritt").bold()
                Text("Beschreibung").bold()
                Text("Dauer").bold()
                Text("")
                
                ForEach(nextSteps, id: \.self) { nextStep in
                    
                    if nextStep.date ?? Date() > Date() {
                        
                        let step = Rational.decimalPlace(nextStep.step, 10)
                        
                        Text(dateCalculation.calculateDateTime(dT: nextStep.date ?? Date()))
                            .font(Font.custom("Avenir Heavy", size: 14))
                        Text(step)
                            .font(Font.custom("Avenir", size: 14))
                        Text(nextStep.instruction ?? "")
                            .font(Font.custom("Avenir", size: 14))
                        Text(Rational.displayHoursMinutes(nextStep.duration))
                            .font(Font.custom("Avenir", size: 14))
                        
                        Button("Erledigt") {

                            managedObjectContext.delete(nextStep)
                            
                            do {
                                try managedObjectContext.save()
                            } catch {
                                // handle the Core Data error
                            }
                        }
                        .font(Font.custom("Avenir", size: 15))
                        .padding()
                        .foregroundColor(.gray)
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            
        }
    }
}
