import BakePlannerCore
import SwiftUI

extension View {
    /// A sheet in the app's language. ContentView sets the app's locale
    /// (English where BakePlanner lacks the device's language) for its
    /// views, but Skip presents a sheet outside their environment: it came
    /// up in the device's language. So every sheet sets the locale again,
    /// the one ContentView handed to the package (AppSettings.locale).
    func appSheet<Content: View>(isPresented: Binding<Bool>,
                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented) {
            content()
                .environment(\.locale, AppSettings.locale)
        }
    }
}
