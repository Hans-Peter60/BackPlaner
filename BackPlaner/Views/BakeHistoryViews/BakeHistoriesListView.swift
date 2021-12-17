//
//  BakeHistoriesView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 06.12.21.


import SwiftUI
import CoreData

struct BakeHistoriesListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(format: "bakeHistoryFlag == true"))
    private var recipes: FetchedResults<Recipe>
    
    @State private var filterBy           = ""
    @State private var bakeHistoryComment = ""
    @State private var bakeHistoryImages  = [Data]()
    
    @State var isBigImageShowing          = false
    
    private var filteredRecipes: [Recipe] {
        
        if filterBy.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            // No filter text, so return all recipes
            return Array(recipes)
        }
        else {
            // Filter by the search term and return
            // a subset of recipes which contain the search term in the name
            return recipes.filter { r in
                return r.bakeHistories.contains(filterBy)
            }
        }
    }
    
    var gridItemLayout = [GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(200), alignment: .leading), GridItem(.flexible(minimum: 180), alignment: .leading), GridItem(.fixed(120), alignment: .leading)]
    var gridItemLayoutImages = [GridItem(.fixed(54), alignment: .leading), GridItem(.fixed(54), alignment: .leading)]
    
    var dateFormat:DateFormat = DateFormat()
    
    var body: some View {
        
        Text("Backhistorie")
            .font(Font.custom("Avenir Heavy", size: 16))
        
        SearchBarView(filterBy: $filterBy)
            .padding([.leading, .trailing, .bottom])
        
        LazyVGrid(columns: gridItemLayout, spacing: 6) {
            
            Text("Datum").bold()
            Text("Rezept").bold()
            Text("Kommentar").bold()
            Text("Bilder").bold()
            Text("")
            Text("")
        }
        .padding(.leading)
        
        ScrollView {
            
            ForEach(filteredRecipes) { recipe in
                
                ForEach(recipe.bakeHistories.allObjects as! [BakeHistory]) { bakeHistory in
                    
                    NavigationLink(
                        destination: BakeHistoryUpdateForm(recipeName: recipe.name, bakeHistory: bakeHistory)
                            .environment(\.managedObjectContext, self.viewContext),
                        label: {
                            
                            VStack {
                                LazyVGrid(columns: gridItemLayout, spacing: 6) {
                                    
                                    Text(dateFormat.calculateDate(dT: bakeHistory.date))
                                        .font(Font.custom("Avenir Heavy", size: 14))
                                    Text(recipe.name)
                                        .font(Font.custom("Avenir Heavy", size: 14))
                                    Text(bakeHistory.comment)
                                        .font(Font.custom("Avenir", size: 14))
                                    
                                    Button("Löschen") {
                                        
                                        viewContext.delete(bakeHistory)
                                        
                                        do {
                                            try viewContext.save()
                                        } catch {
                                            // handle the Core Data error
                                        }
                                    }
                                    .font(Font.custom("Avenir", size: 15))
                                    .padding()
                                    .foregroundColor(.gray)
                                    .buttonStyle(.bordered)
                                    
                                    Text(" ")
                                    Text(" ")
                                    HStack {
                                        if bakeHistory.images != nil {
                                            
                                            // MARK: History Images
                                            ForEach(bakeHistory.images!, id: \.self) { image in
                                                
                                                NavigationLink(
                                                    destination: ShowBigImagesView(images: bakeHistory.images!, index: 0)
                                                )
                                                {
                                                    let i = UIImage(data: image) ?? UIImage()
                                                    Image(uiImage: i)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 50, height: 50, alignment: .center)
                                                        .clipped()
                                                        .cornerRadius(5)
                                                }
                                            }
                                        }
                                        else {
                                            Image("no-image-icon-23494")
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 50, height: 50, alignment: .center)
                                                .clipped()
                                                .cornerRadius(5)
                                            
                                        }
                                        Text(" ")
                                    }
                                }
                            }
                        })
                }
            }
        }
        .padding()
    }
}

//struct BakeHistoriesListView_Previews: PreviewProvider {
//    static var previews: some View {
//        BakeHistoriesListView()
//            .environmentObject(RecipeModel())
//    }
//}

struct BakeHistoryListView: View {
    
    @State private var showingSheet = false
    @State private var selectedBakeHistoryId: NSManagedObjectID?
    
    @Environment(\.managedObjectContext) var moc
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    private var bakeHistories: FetchedResults<BakeHistory>
    
    @State private var filterBy           = ""
    @State private var bakeHistoryComment = ""
    @State private var bakeHistoryImages  = [Data]()
    
    var gridItemLayout = [GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(200), alignment: .leading), GridItem(.flexible(minimum: 180), alignment: .leading), GridItem(.fixed(120), alignment: .leading), GridItem(.fixed(120), alignment: .leading)]
    
    var dateFormat:DateFormat = DateFormat()
    
    var body: some View {
        VStack {
            Form {
                ForEach(bakeHistories, id: \.self) { bakeHistory in
                    Section {
                        BakeHistoryRowView(bakeHistory: bakeHistory)
                            .onTapGesture {
                                self.selectedBakeHistoryId = bakeHistory.objectID
                                self.showingSheet          = true
                            }
                    }
                }
            }
        }
        .navigationBarTitle("Backhistorie").sheet(isPresented: $showingSheet ) {
            EditBakeHistoryView(bakeHistoryId: self.selectedBakeHistoryId!)
                .environment(\.managedObjectContext, self.moc)
        }
    }
}


struct EditBakeHistoryView: View {
    
    var bakeHistoryId: NSManagedObjectID
    
    @Environment(\.presentationMode) var presentationMode
    @State private var comment = ""
    @State private var description = ""
    @Environment(\.managedObjectContext) var moc
    
    var gridItemLayout = [GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(200), alignment: .leading), GridItem(.flexible(minimum: 180), alignment: .leading), GridItem(.fixed(120), alignment: .leading), GridItem(.fixed(120), alignment: .leading)]
    
    var dateFormat:DateFormat = DateFormat()
    
    var bakeHistory: BakeHistory {
        moc.object(with: bakeHistoryId) as! BakeHistory
    }
    
    var body: some View {
        
        NavigationView {
            Form {
                Section {
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        Text(dateFormat.calculateDate(dT: bakeHistory.date))
                            .font(Font.custom("Avenir Heavy", size: 14))
                        Text(bakeHistory.recipe!.name)
                            .font(Font.custom("Avenir Heavy", size: 14))
                        Text(bakeHistory.comment)
                            .font(Font.custom("Avenir", size: 14))
                        if bakeHistory.objectID == nil { Text("objectID = nil") } else { Text("objectID != nil") }
                        //                        HStack {
                        //                            if bakeHistory.images.count > 0 {
                        //                                // MARK: History Images
                        //                                ForEach(0..<bakeHistory.images.count) { index in
                        //
                        //                                    let image = UIImage(data: bakeHistory.images[index]) ?? UIImage()
                        //                                    Image(uiImage: image)
                        //                                        .resizable()
                        //                                        .scaledToFill()
                        //                                        .frame(width: 50, height: 50, alignment: .center)
                        //                                        .clipped()
                        //                                        .cornerRadius(5)
                        //                                }
                        //                            }
                        //                            else {
                        //                                Image("no-image-icon-23494")
                        //                                    .resizable()
                        //                                    .scaledToFill()
                        //                                    .frame(width: 50, height: 50, alignment: .center)
                        //                                    .clipped()
                        //                                    .cornerRadius(5)
                        //                            }
                        //                        }
                    }
                }
            }
            .navigationBarTitle(Text("Editieren"), displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                self.presentationMode.wrappedValue.dismiss()
            }, trailing: Button("Speichern") {
                self.bakeHistory.objectWillChange.send()             // << here !!
                self.bakeHistory.comment = self.comment
                //    self.asset.assetDescription = self.description
                try? self.moc.save()
                
                // better do this at the end of activity
                self.presentationMode.wrappedValue.dismiss()
            }
            )
        }
        .onAppear {
            self.comment = self.bakeHistory.comment
            //            self.description = self.asset.assetDescription
        }
    }
}

struct BakeHistoryRowView: View {
    @ObservedObject var bakeHistory: BakeHistory
    
    var gridItemLayout = [GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(200), alignment: .leading), GridItem(.flexible(minimum: 180), alignment: .leading), GridItem(.fixed(120), alignment: .leading), GridItem(.fixed(120), alignment: .leading)]
    
    var dateFormat:DateFormat = DateFormat()
    
    var body: some View {
        HStack {
            LazyVGrid(columns: gridItemLayout, spacing: 6) {
                
                Text(dateFormat.calculateDate(dT: bakeHistory.date))
                    .font(Font.custom("Avenir Heavy", size: 14))
                if bakeHistory.recipe != nil {
                    Text(bakeHistory.recipe!.name)
                        .font(Font.custom("Avenir Heavy", size: 14))
                } else { Text("") }
                Text(bakeHistory.comment)
                    .font(Font.custom("Avenir", size: 14))
                
                if bakeHistory.objectID == nil { Text("objectID = nil") } else { Text("objectID != nil") }
                
                //                HStack {
                //                    if bakeHistory.images.count > 0 {
                //                        // MARK: History Images
                //                        ForEach(0..<bakeHistory.images.count) { index in
                //
                //                            let image = UIImage(data: bakeHistory.images[index]) ?? UIImage()
                //                            Image(uiImage: image)
                //                                .resizable()
                //                                .scaledToFill()
                //                                .frame(width: 50, height: 50, alignment: .center)
                //                                .clipped()
                //                                .cornerRadius(5)
                //                        }
                //                    }
                //                    else {
                //                        Image("no-image-icon-23494")
                //                            .resizable()
                //                            .scaledToFill()
                //                            .frame(width: 50, height: 50, alignment: .center)
                //                            .clipped()
                //                            .cornerRadius(5)
                //                    }
                //                }
            }
            
            //           Text(asset.assetDescription)
        }
    }
}

