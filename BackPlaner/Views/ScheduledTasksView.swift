//
//  ScheduledTasksView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 03.12.21.
//

import SwiftUI

struct ScheduledTasksView: View {
    
    @EnvironmentObject var manager:LocalNotificationManager
   
    // Tab selection
    @Binding var tabSelection: Int
    
    var body: some View {

        ScrollView {
            
            Text("Liste der nächsten Schritte:")
                .bold()
            
            Divider()
            
            ForEach(manager.notifications) { n in
                
                Text("-> ")
                Text(n.id)
                Text(n.title)
                HStack {
//                    Text(n.datetime.day + "." + n.datetime.month + "." + n.datetime.year)
//                    Text("   " + n.datetime.hour + ":" + n.datetime.minute)
                }
            }
        }
    }
}

//struct ScheduledTasksView_Previews: PreviewProvider {
//    static var previews: some View {
//
//        ScheduledTasksView()
//    }
//}
