//
//  DurationInputTests.swift
//  BackPlanerTests
//

import Testing
@testable import BackPlaner

@Suite("Duration input: hours and minutes as a baker writes them")
struct DurationInputTests {

    @Test("Every spelling comes out as minutes", arguments: [
        ("", 0),
        ("90", 90),
        ("0", 0),
        ("1:30", 90),
        ("0:45", 45),
        ("14:00", 840),
        ("1h", 60),
        ("1 h", 60),
        ("1h30", 90),
        ("1h 30", 90),
        ("1 h 30 min", 90),
        ("1h30m", 90),
        ("1,5 h", 90),
        ("1.5h", 90),
        ("1,5", 90),
        ("0,5", 30),
        ("2 Std", 120),
        ("2 Std.", 120),
        ("14 Stunden", 840),
        ("1 Stunde 15 Minuten", 75),
        ("45 min", 45),
        ("45 Min.", 45),
        ("45m", 45),
        ("30 Minuten", 30),
        ("2 hours 10 minutes", 130),
        ("3 heures", 180),
        ("  60  ", 60)
    ])
    func parses(text: String, expected: Int) {
        #expect(DurationInput.minutes(from: text) == expected, "\(text)")
    }

    @Test("Half-typed or meaningless text is not a duration yet", arguments: ["-", "h", "abc", "1:", "1h x", "-5"])
    func rejects(text: String) {
        #expect(DurationInput.minutes(from: text) == nil, "\(text)")
    }

    @Test("Minutes are shown in hours and minutes and read back the same")
    func roundTrip() {
        #expect(DurationInput.text(forMinutes: 0) == "")
        #expect(DurationInput.text(forMinutes: 45) == "45 min")
        #expect(DurationInput.text(forMinutes: 60) == "1 h")
        #expect(DurationInput.text(forMinutes: 90) == "1 h 30 min")
        #expect(DurationInput.text(forMinutes: 840) == "14 h")

        for minutes in [1, 45, 60, 90, 125, 840, 1455] {
            #expect(DurationInput.minutes(from: DurationInput.text(forMinutes: minutes)) == minutes)
        }
    }
}
