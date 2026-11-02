//
//  PlannedBakeEntries.swift
//  BakePlannerCore
//
//  Setting reminders writes a bake-history entry for the end of the planned
//  bake, so "Letztes Mal" can ask for the result afterwards. When the plan
//  is replaced or deleted, that entry is a ghost: dated in the future, with
//  the placeholder comment, without photos or measurements. It goes with
//  the plan — unless someone has already written into it, which makes it
//  theirs. A starter's plan writes a feeding into its diary the same way,
//  dated at the plan's start and without a result yet; it goes by the same
//  rule. Shared by iOS and Android, so both clean up the same way.
//

import Foundation

public enum PlannedBakeEntries {

    /// Whether an entry is one a plan wrote and nobody has touched: still
    /// ahead of `now`, the placeholder (or nothing) as comment, no photos,
    /// no measurements.
    public static func isUntouched(_ entry: StoredBakeHistory, now: Date = Date()) -> Bool {
        entry.date > now
            && BakeHistoryFacts.isPlaceholderComment(entry.comment)
            && entry.images.isEmpty
            && entry.facts.isEmpty
    }

    /// The untouched planned entries among `entries`.
    public static func untouched(in entries: [StoredBakeHistory], now: Date = Date()) -> [StoredBakeHistory] {
        entries.filter { isUntouched($0, now: now) }
    }

    /// Removes the untouched planned entries of recipe `recipeID` from
    /// `store` — called when the recipe's plan is replaced or deleted.
    /// Returns how many went.
    @discardableResult
    public static func remove(ofRecipe recipeID: String, from store: any BakeHistoryStore,
                              now: Date = Date()) throws -> Int {
        let ghosts = untouched(in: try store.entries(ofRecipe: recipeID, includingImages: false), now: now)
        for ghost in ghosts {
            try store.delete(id: ghost.id)
        }
        return ghosts.count
    }
}

public enum PlannedFeedingEntries {

    /// Whether a feeding is one a plan wrote and nobody has touched: still
    /// ahead of `now`, and without peak time, float test or note.
    public static func isUntouched(_ feeding: StoredStarterFeeding, now: Date = Date()) -> Bool {
        feeding.date > now && feeding.facts.normalized == StarterFeedingFacts()
    }

    /// Removes the untouched planned feedings of recipe `recipeID` from
    /// `store` — called when the starter's plan is replaced or deleted.
    /// Returns how many went.
    @discardableResult
    public static func remove(ofRecipe recipeID: String, from store: any StarterFeedingLogStore,
                              now: Date = Date()) throws -> Int {
        let ghosts = try store.feedings(ofRecipe: recipeID).filter { isUntouched($0, now: now) }
        for ghost in ghosts {
            try store.delete(id: ghost.id)
        }
        return ghosts.count
    }
}
