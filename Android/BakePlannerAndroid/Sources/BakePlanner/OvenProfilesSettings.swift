//
//  OvenProfilesSettings.swift
//  BakePlanner (Android)
//
//  The "Backöfen" section of the settings and the editor for one oven:
//  the ovens one bakes in, each with its preheating times, whether it
//  runs hot or cold and its convection reduction, and which of them the
//  plan proposes. Stored as the iPhone stores them (a JSON array under
//  `settings.ovenProfiles`, the choice under `settings.selectedOvenProfile`),
//  here in the settings file.
//

import BakePlannerCore
import SwiftUI

/// The profiles in the settings file, for the section and the editor.
enum OvenProfileFile {

    static var profiles: [OvenProfile] {
        get {
            guard BakePro.ovenProfilesOpen else { return [] }
            return OvenProfiles.decode(SettingsFile.value(forKey: AppSettingsKeys.ovenProfiles) as? String)
        }
        set {
            // An empty string, not an empty array: "no profiles" means the
            // plain settings are in force.
            SettingsFile.set(newValue.isEmpty ? "" : OvenProfiles.encode(newValue), forKey: AppSettingsKeys.ovenProfiles)
        }
    }

    static var selectedID: String {
        get { SettingsFile.value(forKey: AppSettingsKeys.selectedOvenProfile) as? String ?? "" }
        set { SettingsFile.set(newValue, forKey: AppSettingsKeys.selectedOvenProfile) }
    }

    static func update(_ profile: OvenProfile) {
        var all = profiles
        guard let index = all.firstIndex(where: { $0.id == profile.id }) else { return }
        all[index] = profile
        profiles = all
    }

    /// A new oven with the plain preheating times; the first one becomes
    /// the chosen oven.
    @discardableResult
    static func add() -> OvenProfile {
        var all = profiles
        let profile = OvenProfile(name: String(localized: "Ofen \(all.count + 1)", bundle: .module),
                                  preheatMinutes: AppSettings.storedPreheatTime,
                                  stonePreheatMinutes: AppSettings.storedStonePreheatTime)
        all.append(profile)
        profiles = all
        if all.count == 1 {
            selectedID = profile.id.uuidString
        }
        return profile
    }

    /// Removes the oven; the choice moves to the first remaining one.
    static func remove(_ id: UUID) {
        let all = profiles.filter { $0.id != id }
        profiles = all
        if selectedID == id.uuidString {
            selectedID = all.first?.id.uuidString ?? ""
        }
    }
}

struct OvenProfilesSection: View {

    /// Bumped whenever the section comes back on screen, so the rows show
    /// what the editor changed.
    @State var revision = 0

    var body: some View {
        let _ = revision
        let profiles = OvenProfileFile.profiles
        Section {
            if profiles.count > 1 {
                Picker("Geplant wird mit", selection: Binding(
                    get: { OvenProfiles.selected(from: profiles, selectedID: OvenProfileFile.selectedID)?.id.uuidString ?? "" },
                    set: { OvenProfileFile.selectedID = $0; revision += 1 }
                )) {
                    ForEach(profiles) { profile in
                        Text(verbatim: profile.name).tag(profile.id.uuidString)
                    }
                }
            }
            ForEach(profiles) { profile in
                NavigationLink {
                    OvenProfileEditorView(id: profile.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: profile.name.isEmpty ? String(localized: "Ofen", bundle: .module) : profile.name)
                        Text(verbatim: Self.summary(of: profile))
                            .font(AppFont.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                OvenProfileFile.add()
                revision += 1
            } label: {
                Label("Ofen hinzufügen", systemImage: "plus")
            }
        } header: {
            Text("Backöfen")
        } footer: {
            Text("Jeder Ofen bringt seine Vorheizzeiten mit und sagt, ob er heißer oder kälter läuft, als der Regler zeigt. Der Plan rechnet mit dem gewählten Ofen, die Ofenschritte nennen die Reglereinstellung. Ohne Ofenprofil gelten die Vorheizzeiten unten.")
        }
        .onAppear { revision += 1 }
    }

    /// "20 min · Stein 60 min · läuft 10 °C heißer · Umluft −20 °C".
    static func summary(of profile: OvenProfile) -> String {
        var parts = ["\(profile.preheatMinutes) min",
                     String(localized: "Stein \(profile.stonePreheatMinutes) min", bundle: .module)]
        if profile.runsHotBy > 0 {
            parts.append(String(localized: "läuft \(profile.runsHotBy) °C heißer", bundle: .module))
        } else if profile.runsHotBy < 0 {
            parts.append(String(localized: "läuft \(-profile.runsHotBy) °C kälter", bundle: .module))
        }
        parts.append(String(localized: "Umluft −\(profile.fanReduction) °C", bundle: .module))
        return parts.joined(separator: " · ")
    }
}

/// One oven: its name, preheating times, deviation and fan reduction.
/// Edits are written to the settings as they happen.
struct OvenProfileEditorView: View {

    let id: UUID
    @State var profile: OvenProfile
    @Environment(\.dismiss) var dismiss

    init(id: UUID) {
        self.id = id
        _profile = State(initialValue: OvenProfileFile.profiles.first { $0.id == id } ?? OvenProfile(name: ""))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $profile.name)
            }
            Section {
                Stepper(value: $profile.preheatMinutes, in: 0...120, step: 5) {
                    row("Vorheizzeit", value: "\(profile.preheatMinutes) min")
                }
                Stepper(value: $profile.stonePreheatMinutes, in: 0...180, step: 5) {
                    row("Vorheizzeit mit Backstein", value: "\(profile.stonePreheatMinutes) min")
                }
            } header: {
                Text("Vorheizen")
            }
            Section {
                Stepper(value: $profile.runsHotBy,
                        in: -OvenProfile.maximumDeviation...OvenProfile.maximumDeviation, step: 5) {
                    row("Abweichung", value: deviationText)
                }
                Stepper(value: $profile.fanReduction, in: 5...40, step: 5) {
                    row("Umluft-Abschlag", value: "−\(profile.fanReduction) °C")
                }
            } header: {
                Text("Temperatur")
            } footer: {
                Text("Ein Rezept mit 250 °C stellst Du an diesem Ofen auf \(OvenSettings.text(profile.dialTemperature(for: 250, convection: false))), mit Umluft auf \(OvenSettings.text(profile.dialTemperature(for: 250, convection: true))). Ob Umluft läuft, wählst Du bei jedem Backvorgang im Planungsblatt.")
            }
            Section {
                Button("Ofen löschen", role: .destructive) {
                    OvenProfileFile.remove(id)
                    dismiss()
                }
            }
        }
        .navigationTitle(profile.name.isEmpty ? String(localized: "Ofen", bundle: .module) : profile.name)
        .onChange(of: profile) { _, updated in
            OvenProfileFile.update(updated)
        }
    }

    private var deviationText: String {
        if profile.runsHotBy > 0 {
            return String(localized: "läuft \(profile.runsHotBy) °C heißer", bundle: .module)
        } else if profile.runsHotBy < 0 {
            return String(localized: "läuft \(-profile.runsHotBy) °C kälter", bundle: .module)
        }
        return String(localized: "stimmt mit dem Regler überein", bundle: .module)
    }

    private func row(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(.secondary)
        }
    }
}

/// The oven and the fan of one bake, for the plan sheet and the baking
/// day: a menu of the ovens when there are two or more, the "Umluft"
/// switch as soon as there is one.
struct OvenChoiceRow: View {
    let profiles: [OvenProfile]
    @Binding var ovenProfileID: String
    @Binding var usesConvection: Bool

    var body: some View {
        if !profiles.isEmpty {
            if profiles.count > 1 {
                Picker("Ofen", selection: $ovenProfileID) {
                    ForEach(profiles) { profile in
                        Text(verbatim: profile.name).tag(profile.id.uuidString)
                    }
                }
            }
            Toggle("Umluft", isOn: $usesConvection)
        }
    }
}
