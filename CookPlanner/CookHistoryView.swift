//
//  CookHistoryView.swift
//  CookPlanner
//
//  Everything cooked on the stopwatch, newest first and by month: the
//  photo, the dish, the stars and the note. A row opens its record.
//

import BakePlannerCore
import SwiftUI

struct CookHistoryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var runLog = CookRunLog.shared
    @State private var shownRun: KitchenCookRun?

    /// The records by month, newest month first.
    private var months: [(month: Date, runs: [KitchenCookRun])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: runLog.runs) {
            calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt
        }
        return grouped.keys.sorted(by: >).map { month in
            (month, grouped[month, default: []].sorted { $0.startedAt > $1.startedAt })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if runLog.runs.isEmpty {
                    ContentUnavailableView("Noch nichts gekocht", systemImage: "stopwatch",
                                           description: Text("Wer im Kochmodus die Uhr startet und am Ende das Protokoll sichert, findet das Gericht hier – mit Sternen, Notiz und Foto."))
                } else {
                    List {
                        ForEach(months, id: \.month) { group in
                            Section {
                                ForEach(group.runs) { run in
                                    Button {
                                        shownRun = run
                                    } label: {
                                        row(run)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            runLog.delete(id: run.id)
                                        } label: {
                                            Label("Löschen", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                Text(verbatim: group.month.formatted(.dateTime.month(.wide).year()))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gekocht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(item: $shownRun) { run in
                CookRunView(runID: run.id)
            }
        }
    }

    private func row(_ run: KitchenCookRun) -> some View {
        HStack(spacing: 12) {
            RunThumbnail(run: run, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: run.dishName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(verbatim: run.startedAt.formatted(date: .abbreviated, time: .omitted))
                    Text(verbatim: KitchenCookRun.clockText(run.totalSeconds))
                        .monospacedDigit()
                    if let rating = run.rating {
                        StarsText(rating: rating)
                    }
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                if let note = run.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// The record's photo as a small square, or a stopwatch without one.
struct RunThumbnail: View {
    let run: KitchenCookRun
    let size: CGFloat

    var body: some View {
        Group {
            if let image = CookRunLog.shared.thumbnail(of: run) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(Theme.subtitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.subtitle.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 6))
        .accessibilityHidden(true)
    }
}

/// "★★★★☆" for a rating, read out as "4 von 5 Sternen".
struct StarsText: View {
    let rating: Int

    var body: some View {
        Text(verbatim: String(repeating: "★", count: max(0, min(5, rating)))
             + String(repeating: "☆", count: max(0, 5 - rating)))
            .font(.caption)
            .foregroundColor(Theme.accentText)
            .accessibilityLabel(Text("\(rating) von 5 Sternen"))
    }
}
