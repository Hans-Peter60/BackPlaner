//
//  ScheduledTasksView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 03.12.21.
//

import SwiftUI

struct ScheduledTasksView: View {
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    var nextSteps: FetchedResults<NextSteps>
   
    // Tab selection
    @Binding var tabSelection: Int
    var gridItemLayout = [GridItem(.fixed(110), alignment: .leading), GridItem(.fixed(90), alignment: .center), GridItem(.flexible(minimum: 180), alignment: .leading), GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(120), alignment: .trailing)]
    var dateCalculation:DateCalculation = DateCalculation()
    @State private var name = ""
    
    var body: some View {

        ScrollView {
            
            Text("Liste der nächsten Schritte:")
                .bold()
            
            Divider()
 
            LazyVGrid(columns: gridItemLayout, spacing: 6) {
                
                Text("Beginn").bold()
                Text("Schritt").bold()
                Text("Beschreibung").bold()
                Text("Dauer").bold()
                Text("")

                ForEach(0..<nextSteps.count) { index in
                    
                    if nextSteps[index].date ?? Date() > Date() {
                        
                        if index > 0 {
                            if index == 0 || nextSteps[index].recipeName != nextSteps[index - 1].recipeName {

                                Text("")
                                Text("")
                                Text(nextSteps[index].recipeName ?? "")
                                    .font(Font.custom("Avenir Heavy", size: 16))
                                Text("")
                                Text("")
                            }
                        }

                        let step = Rational.decimalPlace(nextSteps[index].step, 10)
                    
                        Text(dateCalculation.calculateDateTime(dT: nextSteps[index].date ?? Date()))
                            .font(Font.custom("Avenir Heavy", size: 14))
                        Text(step)
                            .font(Font.custom("Avenir", size: 14))
                        Text(nextSteps[index].instruction ?? "")
                            .font(Font.custom("Avenir", size: 14))
                        Text(Rational.displayHoursMinutes(nextSteps[index].duration))
                            .font(Font.custom("Avenir", size: 14))
                        
                        Button("Erledigt") {
                            
                            // ergänzen
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

//struct ScheduledTasksView_Previews: PreviewProvider {
//    static var previews: some View {
//
//        ScheduledTasksView()
//    }
//}
