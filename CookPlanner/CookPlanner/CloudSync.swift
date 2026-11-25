//
//  CloudSync.swift
//  CookPlanner
//
//  The cook's own dishes and the cooking records with their photos, kept
//  alike on every device of the same Apple ID through the private CloudKit
//  database (container iCloud.de.hpm64625.CookPlanner, zone "CookPlanner").
//  No account and no server of our own: CKSyncEngine sends what changed
//  and fetches what other devices changed — at launch, when the app comes
//  to the front, and on CloudKit's silent pushes.
//
//  One record per dish ("Dish", the dish as a one-dish KitchenDishFile in
//  "payload", so a later file format is refused instead of half read) and
//  one per cooking record ("CookRun", the record as JSON in "payload", the
//  photo as the asset "photo"). Record names are "dish-<id>" and
//  "run-<id>". The local stores stay the truth on each device; this class
//  only carries changes between them. When two devices changed the same
//  record, the later change wins — also across a relaunch, as the time of
//  every local change is kept on disk. A save CloudKit refused for lack of
//  space or the like is kept and sent again when the app next comes to the
//  front; a record this build cannot read is never written back by it.
//

import BakePlannerCore
import CloudKit
import Foundation
import Observation

@Observable @MainActor
final class CloudSync: CKSyncEngineDelegate {

    static let shared = CloudSync()
    static let containerID = "iCloud.de.hpm64625.CookPlanner"

    /// Whether iCloud can be used, for the settings.
    enum Status: Equatable {
        case unknown, available, noAccount, restricted, failed(String)
    }

    private(set) var status: Status = .unknown
    private(set) var lastSync: Date?

    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private weak var library: DishLibrary?
    @ObservationIgnored private weak var runLog: CookRunLog?
    @ObservationIgnored private let zoneID = CKRecordZone.ID(zoneName: "CookPlanner")
    /// The CloudKit bookkeeping of every record (change tag and so on),
    /// so the next save of it is not taken for a conflict.
    @ObservationIgnored private var systemFields: [String: Data] = [:]
    /// When a record was last changed here, to decide a conflict; kept
    /// on disk, so an edit made offline still wins after a relaunch.
    @ObservationIgnored private var localEdits: [String: Date] = [:] { didSet { persistExtras() } }
    /// Saves CloudKit turned down for a reason that does not pass by
    /// itself (iCloud full, a limit): sent again at the next chance.
    @ObservationIgnored private var deferredSaves: Set<String> = [] { didSet { persistExtras() } }
    /// Records of a later file format than this build reads: left as they
    /// are on the server, never overwritten from here.
    @ObservationIgnored private var unreadable: Set<String> = [] { didSet { persistExtras() } }
    /// Another Apple ID signed in: whether this device's data goes up to it
    /// is the cook's call, asked in the dish list.
    private(set) var accountSwitchPending = false

    private let folder: URL
    private var stateURL: URL { folder.appendingPathComponent("sync-state.json") }
    private var fieldsURL: URL { folder.appendingPathComponent("sync-records.json") }
    private var extrasURL: URL { folder.appendingPathComponent("sync-extras.json") }

    /// What is kept besides the engine's own state.
    private struct Extras: Codable {
        var localEdits: [String: Date] = [:]
        var deferredSaves: Set<String> = []
        var unreadable: Set<String> = []
    }
    @ObservationIgnored private var loadingExtras = false

    private init() {
        folder = URL.applicationSupportDirectory.appendingPathComponent("CookPlanner", isDirectory: true)
    }

    // MARK: Starting

    /// Starts the engine once; on the very first start everything already
    /// on this device is sent, so the dishes of before the sync come along.
    func start(library: DishLibrary, runLog: CookRunLog) {
        guard engine == nil else { return }
        self.library = library
        self.runLog = runLog
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fieldsURL),
           let fields = try? JSONDecoder().decode([String: Data].self, from: data) {
            systemFields = fields
        }
        if let data = try? Data(contentsOf: extrasURL), let extras = try? JSONDecoder().decode(Extras.self, from: data) {
            loadingExtras = true
            localEdits = extras.localEdits
            deferredSaves = extras.deferredSaves
            unreadable = extras.unreadable
            loadingExtras = false
        }
        let state = (try? Data(contentsOf: stateURL))
            .flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let container = CKContainer(identifier: Self.containerID)
        let configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                       stateSerialization: state, delegate: self)
        engine = CKSyncEngine(configuration)
        if state == nil { sendEverything() }
        retryDeferredSaves()
        Task { await refreshStatus() }
    }

    /// Queues the saves CloudKit refused earlier once more.
    private func retryDeferredSaves() {
        guard let engine, !deferredSaves.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: deferredSaves.map { .saveRecord(recordID($0)) })
        deferredSaves = []
    }

    private func persistExtras() {
        guard !loadingExtras else { return }
        let extras = Extras(localEdits: localEdits, deferredSaves: deferredSaves, unreadable: unreadable)
        if let data = try? JSONEncoder().encode(extras) { try? data.write(to: extrasURL, options: .atomic) }
    }

    /// The answer to the question after an account switch: whether this
    /// device's dishes and records go up to the new Apple ID too.
    func resolveAccountSwitch(uploadLocalData: Bool) {
        accountSwitchPending = false
        if uploadLocalData { sendEverything() }
    }

    /// Fetches what the other devices changed; the app calls it when it
    /// comes to the front.
    func fetchNow() async {
        guard let engine else { return }
        await refreshStatus()
        retryDeferredSaves()
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            lastSync = .now
        } catch {
            // The engine retries by itself; the settings show the status.
        }
    }

    private func refreshStatus() async {
        do {
            switch try await CKContainer(identifier: Self.containerID).accountStatus() {
            case .available: status = .available
            case .noAccount: status = .noAccount
            case .restricted, .temporarilyUnavailable: status = .restricted
            default: status = .unknown
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func sendEverything() {
        guard let engine else { return }
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        let names = (library?.dishes.map { "dish-" + $0.id } ?? []) + (runLog?.runs.map { "run-" + $0.id } ?? [])
        engine.state.add(pendingRecordZoneChanges: names.map { .saveRecord(recordID($0)) })
    }

    // MARK: Local changes

    func dishChanged(_ id: String) { noteSave("dish-" + id) }
    func dishDeleted(_ id: String) { noteDelete("dish-" + id) }
    func runChanged(_ id: String) { noteSave("run-" + id) }
    func runDeleted(_ id: String) { noteDelete("run-" + id) }

    private func noteSave(_ name: String) {
        guard let engine else { return }
        localEdits[name] = .now
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(name))])
    }

    private func noteDelete(_ name: String) {
        guard let engine else { return }
        localEdits[name] = nil
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(name))])
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    // MARK: Records

    /// The record for a pending save, from what this device has now; nil
    /// when the dish or record is gone meanwhile.
    private func record(for id: CKRecord.ID) -> CKRecord? {
        let name = id.recordName
        // What this build could not read it does not write over.
        guard !unreadable.contains(name) else { return nil }
        if name.hasPrefix("dish-") {
            guard let dish = library?.dish(id: String(name.dropFirst(5))),
                  let data = try? KitchenDishFile(dishes: [dish]).encoded() else { return nil }
            let record = baseRecord(type: "Dish", id: id)
            record["payload"] = data as CKRecordValue
            return record
        }
        if name.hasPrefix("run-") {
            guard let run = runLog?.run(id: String(name.dropFirst(4))),
                  let data = try? Self.runEncoder.encode(run) else { return nil }
            let record = baseRecord(type: "CookRun", id: id)
            record["payload"] = data as CKRecordValue
            if let url = runLog?.photoURL(of: run) {
                record["photo"] = CKAsset(fileURL: url)
            } else {
                record["photo"] = nil as CKAsset?
            }
            return record
        }
        return nil
    }

    /// The record with its last known bookkeeping, or a new one.
    private func baseRecord(type: CKRecord.RecordType, id: CKRecord.ID) -> CKRecord {
        if let data = systemFields[id.recordName], let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            defer { coder.finishDecoding() }
            if let record = CKRecord(coder: coder) { return record }
        }
        return CKRecord(recordType: type, recordID: id)
    }

    private func remember(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        systemFields[record.recordID.recordName] = coder.encodedData
    }

    private func persistFields() {
        if let data = try? JSONEncoder().encode(systemFields) { try? data.write(to: fieldsURL, options: .atomic) }
    }

    /// What a fetched record holds, once read.
    private enum Fetched {
        case dish(KitchenDish)
        case run(KitchenCookRun, photo: URL?)
    }

    /// Reads a record another device changed; nil when this build cannot
    /// read it — a later file format — in which case the record is left
    /// alone on the server and not written back from here.
    private func read(_ record: CKRecord) -> Fetched? {
        let name = record.recordID.recordName
        guard let data = record["payload"] as? Data else { return nil }
        let fetched: Fetched?
        switch record.recordType {
        case "Dish":
            fetched = (try? KitchenDishFile.decode(data).kitchenDishes.first).map(Fetched.dish)
        case "CookRun":
            fetched = (try? Self.runDecoder.decode(KitchenCookRun.self, from: data))
                .map { Fetched.run($0, photo: (record["photo"] as? CKAsset)?.fileURL) }
        default:
            fetched = nil
        }
        if fetched == nil {
            unreadable.insert(name)
        } else {
            remember(record)
            localEdits[name] = nil
            if unreadable.contains(name) { unreadable.remove(name) }
        }
        return fetched
    }

    /// Takes a record another device changed into this device's stores.
    private func apply(_ record: CKRecord) {
        switch read(record) {
        case .dish(let dish): library?.applyRemote(dish)
        case .run(let run, let photo): runLog?.applyRemote(run, photoFile: photo)
        case nil: break
        }
    }

    /// Takes a whole fetch into the stores at once: one database reload and
    /// one write of the record file, not one per record.
    private func apply(_ records: [CKRecord]) {
        var dishes = [KitchenDish]()
        var runs = [(KitchenCookRun, URL?)]()
        for record in records {
            switch read(record) {
            case .dish(let dish): dishes.append(dish)
            case .run(let run, let photo): runs.append((run, photo))
            case nil: break
            }
        }
        if !dishes.isEmpty { library?.applyRemote(dishes) }
        if !runs.isEmpty { runLog?.applyRemote(runs) }
    }

    private func removeLocal(_ name: String) {
        systemFields[name] = nil
        localEdits[name] = nil
        unreadable.remove(name)
        deferredSaves.remove(name)
        if name.hasPrefix("dish-") { library?.removeRemote(id: String(name.dropFirst(5))) }
        if name.hasPrefix("run-") { runLog?.removeRemote(id: String(name.dropFirst(4))) }
    }

    private static let runEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let runDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                try? data.write(to: stateURL, options: .atomic)
            }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                sendEverything()
            case .switchAccounts:
                // Another Apple ID: this device's dishes stay. Whether they
                // go up to the new account too — they may be someone
                // else's — is asked, not assumed.
                systemFields = [:]
                persistFields()
                unreadable = []
                deferredSaves = []
                accountSwitchPending = true
            case .signOut:
                systemFields = [:]
                persistFields()
                unreadable = []
                deferredSaves = []
            @unknown default:
                break
            }
            await refreshStatus()

        case .fetchedDatabaseChanges(let changes):
            // The zone was removed (iCloud data deleted in the settings):
            // the dishes here stay and are sent again.
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                systemFields = [:]
                persistFields()
                sendEverything()
            }

        case .fetchedRecordZoneChanges(let changes):
            apply(changes.modifications.map(\.record))
            for deletion in changes.deletions { removeLocal(deletion.recordID.recordName) }
            persistFields()
            lastSync = .now

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                remember(record)
                localEdits[record.recordID.recordName] = nil
                deferredSaves.remove(record.recordID.recordName)
            }
            for id in sent.deletedRecordIDs {
                systemFields[id.recordName] = nil
                deferredSaves.remove(id.recordName)
            }
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            for failure in sent.failedRecordSaves {
                let id = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    // Changed on another device too: the later change wins.
                    guard let server = failure.error.serverRecord else { break }
                    if let local = localEdits[id.recordName], local > (server.modificationDate ?? .distantPast) {
                        remember(server)
                        retry.append(.saveRecord(id))
                    } else {
                        apply(server)
                    }
                case .zoneNotFound:
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    systemFields[id.recordName] = nil
                    retry.append(.saveRecord(id))
                case .unknownItem:
                    systemFields[id.recordName] = nil
                    retry.append(.saveRecord(id))
                case .quotaExceeded, .limitExceeded, .assetFileNotFound, .assetFileModified,
                     .serverRejectedRequest, .batchRequestFailed:
                    // The engine drops these; kept here and sent again when
                    // the app next comes to the front — by then iCloud may
                    // have room, the photo may be in place.
                    deferredSaves.insert(id.recordName)
                default:
                    // Network, rate limits and the like: the engine tries again.
                    break
                }
            }
            if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }
            persistFields()
            lastSync = .now

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        // The records are made here, on the main actor where the stores
        // live; the batch only looks them up.
        var records: [CKRecord.ID: CKRecord] = [:]
        for change in pending {
            if case .saveRecord(let id) = change, let record = record(for: id) { records[id] = record }
        }
        let ready = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in ready[id] }
    }
}
