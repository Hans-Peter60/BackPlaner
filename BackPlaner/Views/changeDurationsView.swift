//
//  changeDurationsView.swift
//  BackPlaner2
//
//  Created by Hans-Peter Müller on 01.12.21.
//

import SwiftUI

struct changeDurationsView: View {
    
    @Binding var instructions: [InstructionFB]
    
    @State private var i = [InstructionFB]()
    @State private var durationHours = ""
    @State private var durationMinutes = ""
    
    var body: some View {
        
        VStack {
            ForEach(instructions) { i in
                HStack {
                    Text(i.instruction)
                    Text(Rational.displayHoursMinutes(i.duration))
                    TextField("Stunden", text:$durationHours)
                    TextField("Minuten", text:$durationMinutes)
                }
            }
        }
    }
}

//struct changeDurationsView_Previews: PreviewProvider {
//    static var previews: some View {
//        changeDurationsView()
//    }
//}
