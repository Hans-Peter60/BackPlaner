import SwiftUI

/// The one-time agreement before the first recipe goes public — the
/// iPhone's EULAView, with its texts (Google Play asks the same of apps
/// with content of users as the App Store does).
struct TermsView: View {
    /// Called after accepting; the pending publication goes on from here.
    let onAccept: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nutzungsbedingungen für öffentliche Rezepte")
                    .font(.title3)
                    .bold()
                Text("Wenn Du ein Rezept öffentlich teilst, wird es für alle Nutzer der Rezept-Datenbank sichtbar.\n\nEs gilt eine Null-Toleranz-Politik gegenüber anstößigen, beleidigenden, rechtswidrigen oder urheberrechtsverletzenden Inhalten. Du bist allein verantwortlich für die von Dir geteilten Inhalte.\n\nGemeldete Inhalte werden geprüft und innerhalb von 24 Stunden entfernt. Autoren, die wiederholt gegen diese Regeln verstoßen, können ausgeschlossen werden.\n\nMit „Akzeptieren“ bestätigst Du, dass Du diese Bedingungen einhältst.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Bevor Du teilst")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Ablehnen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Akzeptieren") {
                    onAccept()
                    dismiss()
                }
            }
        }
    }
}
