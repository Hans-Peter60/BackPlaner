//
//  CookRunView.swift
//  CookPlanner
//
//  One stopwatch record: how it turned out — stars, a note, a photo of the
//  plate — then the total against the plan, and each step with the moment
//  it was done, how long it took and the difference to the plan.
//

import BakePlannerCore
import PhotosUI
import SwiftUI

struct CookRunView: View {

    let runID: String
    @Environment(\.dismiss) private var dismiss
    @State private var runLog = CookRunLog.shared
    @State private var note = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var showingPhoto = false
    @FocusState private var editingNote: Bool

    var body: some View {
        NavigationStack {
            if let run = runLog.run(id: runID) {
                content(run)
            } else {
                ContentUnavailableView("Protokoll gelöscht", systemImage: "stopwatch")
            }
        }
        .onAppear { note = runLog.run(id: runID)?.note ?? "" }
        .onDisappear { saveNote() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = CookRunLog.downsampled(data) {
                    runLog.setPhoto(image, for: runID)
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraPicker { image in runLog.setPhoto(image, for: runID) }
                .ignoresSafeArea()
        }
    }

    private func saveNote() {
        guard var run = runLog.run(id: runID) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard run.note != value else { return }
        run.note = value
        runLog.update(run)
    }

    private func setRating(_ stars: Int) {
        guard var run = runLog.run(id: runID) else { return }
        run.rating = run.rating == stars ? nil : stars
        runLog.update(run)
    }

    /// How it turned out: stars, the note and the photo.
    @ViewBuilder
    private func impressionSection(_ run: KitchenCookRun) -> some View {
        Section {
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { stars in
                    Button {
                        setRating(stars)
                    } label: {
                        Image(systemName: stars <= (run.rating ?? 0) ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundColor(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(stars) Sterne"))
                }
            }
            TextField("Notiz, z. B. „beim nächsten Mal weniger Salz“", text: $note, axis: .vertical)
                .lineLimit(2...6)
                .focused($editingNote)
                .onSubmit { saveNote() }
            if let photo = runLog.photo(of: run) {
                Button {
                    showingPhoto = true
                } label: {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Foto vergrößern")
                .sheet(isPresented: $showingPhoto) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .presentationDragIndicator(.visible)
                }
            }
            HStack {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        takingPhoto = true
                    } label: {
                        Label("Foto aufnehmen", systemImage: "camera")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(run.photoFileName == nil ? "Foto wählen" : "Anderes Foto", systemImage: "photo")
                }
                .buttonStyle(.borderless)
                if run.photoFileName != nil {
                    Spacer()
                    Button(role: .destructive) {
                        runLog.removePhoto(of: runID)
                    } label: {
                        Label("Entfernen", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Wie war’s?")
        }
    }

    @ViewBuilder
    private func content(_ run: KitchenCookRun) -> some View {
            List {
                impressionSection(run)
                if run.isManualEntry {
                    // Entered by hand or from a photo: only the day can change.
                    Section {
                        DatePicker("Gekocht am", selection: Binding(get: { run.startedAt }, set: { date in
                            guard var changed = runLog.run(id: runID) else { return }
                            changed.startedAt = date
                            runLog.update(changed)
                        }), in: ...Date.now)
                    } footer: {
                        Text("Ohne Stoppuhr eingetragen.")
                    }
                } else {
                stopwatchSections(run)
                }
            }
            .navigationTitle(Text(verbatim: run.dishName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        saveNote()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") {
                        editingNote = false
                        saveNote()
                    }
                }
            }
    }

    /// What the stopwatch measured: the total against the plan, the steps.
    @ViewBuilder
    private func stopwatchSections(_ run: KitchenCookRun) -> some View {
                Section {
                    LabeledContent("Gebraucht") {
                        Text(verbatim: KitchenCookRun.clockText(run.totalSeconds))
                            .monospacedDigit()
                    }
                    LabeledContent("Geplant") {
                        Text(verbatim: KitchenCookRun.clockText(run.plannedMinutes * 60))
                            .monospacedDigit()
                    }
                    if run.relaxed == true {
                        Label("Entspannt gekocht, ohne Uhr – die Zeiten zählen nicht für die gemessenen Zeiten.", systemImage: "leaf")
                            .font(.footnote)
                            .foregroundColor(Theme.good)
                    } else if run.isComplete {
                        LabeledContent("Unterschied") {
                            let difference = run.totalSeconds - run.plannedMinutes * 60
                            Text(verbatim: KitchenCookRun.differenceText(difference))
                                .monospacedDigit()
                                .foregroundColor(difference > 0 ? Theme.warning : Theme.good)
                        }
                    } else if let total = run.totalSteps {
                        Text("Vorzeitig beendet: \(run.steps.count) von \(total) Schritten erledigt.")
                            .foregroundColor(Theme.warning)
                    }
                } header: {
                    Text(verbatim: run.startedAt.formatted(date: .abbreviated, time: .shortened))
                }

                Section {
                    ForEach(run.steps, id: \.taskID) { step in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: step.name)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: step.tickedByCook ? "checkmark.circle" : "timer")
                                Text("erledigt \(KitchenCookRun.clockText(step.doneSecond)) · gebraucht \(KitchenCookRun.clockText(step.actualSeconds)) · geplant \(step.plannedMinutes) Min.")
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(verbatim: KitchenCookRun.differenceText(step.differenceSeconds))
                                    .foregroundColor(step.differenceSeconds > 60 ? Theme.warning
                                                     : step.differenceSeconds < -60 ? Theme.good : .secondary)
                            }
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.secondary)
                            if !step.component.isEmpty {
                                Text(verbatim: step.component)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Schritte")
                } footer: {
                    Text("Ein Handschritt zählt ab dem vorigen Abhaken – oder ab der Minute, für die der Plan ihn vorsah, wenn die später lag – bis zu seinem eigenen. Schritte mit Uhr-Symbol liefen von allein und endeten nach Plan.")
                }
    }
}

/// The camera for one photo of the plate.
struct CameraPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPicked(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
