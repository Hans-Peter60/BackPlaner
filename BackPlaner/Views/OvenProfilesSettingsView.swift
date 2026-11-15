//
//  OvenProfilesSettingsView.swift
//  BackPlaner
//
//  The "Backöfen" section of the settings: the ovens one bakes in, which
//  of them the plan works with, and the editor for one oven. A Pro feature:
//  adding an oven goes through the paywall when locked.
//

import BakePlannerCore
import SwiftUI

struct OvenProfilesSection: View {

    /// The oven just added, whose editor the settings push right away: the
    /// destination has to sit on the Form, not on this section — a Section
    /// with a modifier is no longer a section to the Form.
    @Binding var newProfileID: UUID?

    @AppStorage(AppSettingsKeys.ovenProfiles) private var profilesJSON = ""
    @AppStorage(AppSettingsKeys.selectedOvenProfile) private var selectedID = ""
    @AppStorage(AppSettingsKeys.preheatTime) private var preheatTime = AppSettings.defaultPreheatTime
    @AppStorage(AppSettingsKeys.stonePreheatTime) private var stonePreheatTime = AppSettings.defaultStonePreheatTime

    private var profiles: [OvenProfile] { OvenProfiles.decode(profilesJSON) }

    var body: some View {
        Section {
            if profiles.count > 1 {
                Picker("Geplant wird mit", selection: selectionBinding) {
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.id.uuidString)
                    }
                }
            }

            ForEach(profiles) { profile in
                NavigationLink {
                    OvenProfileEditorView(id: profile.id)
                } label: {
                    row(profile)
                }
            }
            .onDelete { offsets in
                for id in offsets.map({ profiles[$0].id }) {
                    OvenProfileStorage.remove(id)
                }
            }

            ProGate(.ovenProfiles) {
                Button {
                    add()
                } label: {
                    Label("Ofen hinzufügen", systemImage: "plus")
                }
            } label: {
                Label("Ofen hinzufügen", systemImage: "plus")
                    .foregroundStyle(.primary)
                Spacer()
            }
        } header: {
            Text("Backöfen")
        } footer: {
            Text("Jeder Ofen bringt seine Vorheizzeiten mit und sagt, ob er heißer oder kälter läuft, als der Regler zeigt. Der Plan rechnet mit dem gewählten Ofen, die Ofenschritte nennen die Reglereinstellung. Ohne Ofenprofil gelten die Vorheizzeiten unten.")
        }
    }

    // MARK: Rows

    private func row(_ profile: OvenProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile.name.isEmpty ? String(localized: "Ofen") : profile.name)
            Text(summary(of: profile))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// "20 min · Stein 60 min · läuft 10 °C heißer · Umluft −20 °C".
    private func summary(of profile: OvenProfile) -> String {
        var parts = ["\(profile.preheatMinutes) min",
                     String(localized: "Stein \(profile.stonePreheatMinutes) min")]
        if profile.runsHotBy > 0 {
            parts.append(String(localized: "läuft \(profile.runsHotBy) °C heißer"))
        } else if profile.runsHotBy < 0 {
            parts.append(String(localized: "läuft \(-profile.runsHotBy) °C kälter"))
        }
        parts.append(String(localized: "Umluft −\(profile.fanReduction) °C"))
        return parts.joined(separator: " · ")
    }

    // MARK: Storage

    private var selectionBinding: Binding<String> {
        Binding(
            get: { OvenProfiles.selected(from: profiles, selectedID: selectedID)?.id.uuidString ?? "" },
            set: { selectedID = $0 }
        )
    }

    /// A new oven starts with the plain preheating times, so nothing changes
    /// in the plan until the baker edits it.
    private func add() {
        var all = profiles
        let profile = OvenProfile(name: String(localized: "Ofen \(all.count + 1)"),
                                  preheatMinutes: preheatTime, stonePreheatMinutes: stonePreheatTime)
        all.append(profile)
        profilesJSON = OvenProfiles.encode(all)
        if all.count == 1 {
            selectedID = profile.id.uuidString
        }
        newProfileID = profile.id
    }
}

/// The profiles in UserDefaults, for the section and the editor alike.
enum OvenProfileStorage {

    static var profiles: [OvenProfile] {
        get { OvenProfiles.decode(UserDefaults.standard.string(forKey: AppSettingsKeys.ovenProfiles)) }
        set {
            // An empty string, not an empty array: the settings view treats
            // "no profiles" as the plain settings being in force.
            UserDefaults.standard.set(newValue.isEmpty ? "" : OvenProfiles.encode(newValue),
                                      forKey: AppSettingsKeys.ovenProfiles)
        }
    }

    static func update(_ profile: OvenProfile) {
        var all = profiles
        guard let index = all.firstIndex(where: { $0.id == profile.id }) else { return }
        all[index] = profile
        profiles = all
    }

    /// Removes the oven; the choice moves to the first remaining one.
    static func remove(_ id: UUID) {
        let all = profiles.filter { $0.id != id }
        profiles = all
        if UserDefaults.standard.string(forKey: AppSettingsKeys.selectedOvenProfile) == id.uuidString {
            UserDefaults.standard.set(all.first?.id.uuidString ?? "", forKey: AppSettingsKeys.selectedOvenProfile)
        }
    }
}

/// One oven: its name, preheating times, deviation and fan reduction. Edits
/// are written to the settings as they happen.
struct OvenProfileEditorView: View {

    let id: UUID

    @State private var profile: OvenProfile
    @Environment(\.dismiss) private var dismiss

    init(id: UUID) {
        self.id = id
        _profile = State(initialValue: OvenProfileStorage.profiles.first { $0.id == id } ?? OvenProfile(name: ""))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $profile.name)
            }

            Section("Vorheizen") {
                Stepper(value: $profile.preheatMinutes, in: 0...120, step: 5) {
                    LabeledContent("Vorheizzeit", value: "\(profile.preheatMinutes) min")
                }
                Stepper(value: $profile.stonePreheatMinutes, in: 0...180, step: 5) {
                    LabeledContent("Vorheizzeit mit Backstein", value: "\(profile.stonePreheatMinutes) min")
                }
            }

            Section {
                // Positive: the oven is hotter than its dial says, so the
                // dial goes down by that much.
                Stepper(value: $profile.runsHotBy,
                        in: -OvenProfile.maximumDeviation...OvenProfile.maximumDeviation, step: 5) {
                    LabeledContent("Abweichung", value: deviationText)
                }
                // Whether the fan runs is chosen per bake in the planning
                // sheet; the oven only knows by how much it is turned down.
                Stepper(value: $profile.fanReduction, in: 5...40, step: 5) {
                    LabeledContent("Umluft-Abschlag", value: "−\(profile.fanReduction) °C")
                }
            } header: {
                Text("Temperatur")
            } footer: {
                Text("Ein Rezept mit 250 °C stellst Du an diesem Ofen auf \(OvenSettings.text(profile.dialTemperature(for: 250, convection: false))), mit Umluft auf \(OvenSettings.text(profile.dialTemperature(for: 250, convection: true))). Ob Umluft läuft, wählst Du bei jedem Backvorgang im Planungsblatt.")
            }

            Section {
                Button("Ofen löschen", role: .destructive) {
                    OvenProfileStorage.remove(id)
                    dismiss()
                }
            }
        }
        .navigationTitle(profile.name.isEmpty ? String(localized: "Ofen") : profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: profile) { _, updated in
            OvenProfileStorage.update(updated)
        }
    }

    private var deviationText: String {
        if profile.runsHotBy > 0 {
            return String(localized: "läuft \(profile.runsHotBy) °C heißer")
        } else if profile.runsHotBy < 0 {
            return String(localized: "läuft \(-profile.runsHotBy) °C kälter")
        }
        return String(localized: "stimmt mit dem Regler überein")
    }
}
