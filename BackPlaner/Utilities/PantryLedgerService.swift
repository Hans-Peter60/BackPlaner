//
//  PantryLedgerService.swift
//  BackPlaner
//
//  The pantry's bookings on this device: a plan put into effect reserves
//  what its bread uses, a plan removed releases, a plan that has ended
//  turns its reservations into deductions. Called from the few places that
//  create or remove plans, and once more whenever the app comes forward,
//  so a plan another device removed or that ended while the app was away
//  is booked as well. The arithmetic is PantryLedger in the package.
//

import BakePlannerCore
import CoreData
import Foundation

enum PantryLedgerService {

    /// Reserves what the plan's bread uses of the available pantry, item by
    /// item, under the plan's id. Nothing while the pantry is locked.
    static func reserve(recipe: RecipeExportData, planID: UUID, scale: Double, planEnd: Date, in context: NSManagedObjectContext) {
        // Plans are put into effect from the main actor (views, the
        // foreground pass); the entitlements live there.
        guard MainActor.assumeIsolated({ Entitlements.shared.isUnlocked(.pantry) }) else { return }
        let items = CoreDataPantryStore(context: context)
        let reservations = CoreDataPantryReservationStore(context: context)
        do {
            // A plan replaced under the same id must not reserve twice.
            try reservations.delete(planID: planID)
            let available = PantryLedger.available(try items.items(), reservations: try reservations.reservations())
            for deduction in PantryMatcher.deductions(for: recipe, scale: scale, pantry: available) where deduction.taken > 0 {
                _ = try reservations.add(planID: planID, recipeName: recipe.name, itemID: deduction.item.uuid,
                                         amount: deduction.taken, unit: deduction.item.unit, planEnd: planEnd)
            }
        } catch {
            AppLog.persistence.error("Reserving the pantry for \(recipe.name) failed: \(error)")
        }
    }

    /// Releases every reservation of these plans — a plan deleted.
    static func release(planIDs: some Sequence<UUID>, in context: NSManagedObjectContext) {
        let store = CoreDataPantryReservationStore(context: context)
        for planID in Set(planIDs) {
            do { try store.delete(planID: planID) } catch {
                AppLog.persistence.error("Releasing the pantry for plan \(planID) failed: \(error)")
            }
        }
    }

    /// Releases the reservations of every plan of the recipe — the plans
    /// replaced by a new one.
    static func release(recipeName: String, in context: NSManagedObjectContext) {
        let store = CoreDataPantryReservationStore(context: context)
        guard let all = try? store.reservations() else { return }
        release(planIDs: all.filter { $0.recipeName == recipeName }.map(\.planID), in: context)
    }

    /// Turns every reservation whose plan has ended into a deduction and
    /// notes the booking so it can be undone. Run when the app comes
    /// forward and after a step is marked done.
    @MainActor
    static func reconcile(in context: NSManagedObjectContext, now: Date = Date()) {
        let itemStore = CoreDataPantryStore(context: context)
        let reservationStore = CoreDataPantryReservationStore(context: context)
        do {
            let due = PantryLedger.dueForConversion(try reservationStore.reservations(), now: now)
            guard !due.isEmpty else { return }
            var items = try itemStore.items()
            for reservation in due {
                if let index = items.firstIndex(where: { $0.uuid == reservation.itemID }) {
                    let after = PantryLedger.converted(items[index], by: reservation)
                    try itemStore.update(after)
                    items[index] = after
                    PantryBookings.record(PantryBooking(date: now, recipeName: reservation.recipeName, itemID: reservation.itemID,
                                                        itemName: after.name, amount: reservation.amount, unit: reservation.unit))
                }
                // The item is gone: nothing to take from, the reservation goes too.
                try reservationStore.delete(id: reservation.id)
            }
        } catch {
            AppLog.persistence.error("Booking the ended plans against the pantry failed: \(error)")
        }
    }

    /// Puts a booking back: the amount returns to the item, the booking
    /// leaves the list.
    static func undo(_ booking: PantryBooking, in context: NSManagedObjectContext) {
        let itemStore = CoreDataPantryStore(context: context)
        do {
            if var item = try itemStore.items().first(where: { $0.uuid == booking.itemID }) {
                let base = item.baseAmount + booking.amount * (booking.unit.grams ?? 1)
                item.amount = base / (item.unit.grams ?? 1)
                try itemStore.update(item)
            }
            PantryBookings.remove(booking)
        } catch {
            AppLog.persistence.error("Undoing a pantry booking failed: \(error)")
        }
    }
}

/// The last deductions made when plans ended, kept on this device so one
/// can be undone when a bread was not baked after all.
enum PantryBookings {
    static let defaultsKey = "pantryBookings"
    static let kept = 20

    static func all(defaults: UserDefaults = .standard) -> [PantryBooking] {
        guard let data = defaults.data(forKey: defaultsKey),
              let bookings = try? JSONDecoder().decode([PantryBooking].self, from: data) else { return [] }
        return bookings
    }

    static func record(_ booking: PantryBooking, defaults: UserDefaults = .standard) {
        var bookings = all(defaults: defaults)
        bookings.insert(booking, at: 0)
        save(Array(bookings.prefix(kept)), defaults: defaults)
    }

    static func remove(_ booking: PantryBooking, defaults: UserDefaults = .standard) {
        save(all(defaults: defaults).filter { $0.id != booking.id }, defaults: defaults)
    }

    private static func save(_ bookings: [PantryBooking], defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(bookings) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
