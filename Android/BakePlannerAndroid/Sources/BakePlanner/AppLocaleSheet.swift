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
                .compactTextFields()
        }
    }

    /// Text fields as high as their text, not Material's 56 dp minimum:
    /// Skip draws every TextField as a Material 3 outlined field, which
    /// reserves room for a floating label the app never uses. Skip's
    /// `textFieldContentPadding` drops the minimum height along with the
    /// default padding. An environment setting, so it has to be applied at
    /// the root and in every sheet (as the locale is). On the Apple build
    /// of this app the modifier does not exist, and the fields are small
    /// anyway.
    func compactTextFields() -> some View {
        #if os(Android)
        return textFieldContentPadding(top: 6, leading: 12, bottom: 6, trailing: 12)
        #else
        return self
        #endif
    }
}
