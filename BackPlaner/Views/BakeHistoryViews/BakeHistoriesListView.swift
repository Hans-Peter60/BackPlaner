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
    @State private var nameOrTag          = 1
    @State private var rating             = 0
    @State private var bakeHistoryComment = ""
    @State private var bakeHistoryImages  = [Data]()
    
    @State var isBigImageShowing          = false
    
    private var filteredRecipes: [Recipe] {
        
        if filterBy.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            // No filter text, so return all recipes
            return recipes.filter { r in
                return r.rating >= rating
            }
        }
        else {
            // Filter by the search term and return
            // a subset of recipes which contain the search term in the name
            if nameOrTag == 1 {
                return recipes.filter { r in
                    return r.bakeHistories.contains(filterBy)
                }
            }
            else {
                return recipes.filter { r in
                    return r.bakeHistories.contains(filterBy)
                }
            }
        }

    }
    
    var gridItemLayout       = [GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(200), alignment: .leading), GridItem(.flexible(minimum: 180), alignment: .leading), GridItem(.fixed(120), alignment: .leading)]
    var gridItemLayoutImages = [GridItem(.fixed(54), alignment: .leading), GridItem(.fixed(54), alignment: .leading)]
    
    var dateFormat:DateFormat = DateFormat()
    
    var body: some View {
        
        Text("Backhistorie")
            .font(Font.custom("Avenir Heavy", size: 16))
        
        SearchBarView(filterBy: $filterBy, nameOrTag: $nameOrTag, rating: $rating, showRating: true)
            .padding([.leading, .trailing, .bottom])
        
        LazyVGrid(columns: gridItemLayout, spacing: 6) {
            
            Text("Datum").bold()
            Text("Rezept").bold()
            Text("Kommentar").bold()
            Text("")
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
                                            Image(GlobalVariables.noImage)
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
                    }
                }
            }
            .navigationBarTitle(Text("Editieren"), displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                self.presentationMode.wrappedValue.dismiss()
            }, trailing: Button("Speichern") {
                self.bakeHistory.objectWillChange.send()
                self.bakeHistory.comment = self.comment

                try? self.moc.save()
                
                self.presentationMode.wrappedValue.dismiss()
            }
            )
        }
        .onAppear {
            self.comment = self.bakeHistory.comment
        }
    }
}
