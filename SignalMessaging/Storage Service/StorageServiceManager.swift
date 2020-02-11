//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSStorageServiceManager)
public class StorageServiceManager: NSObject, StorageServiceManagerProtocol {

    @objc
    public static let shared = StorageServiceManager()

    var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.willResignActive),
                name: .OWSApplicationWillResignActive,
                object: nil
            )

            guard self.tsAccountManager.isRegisteredAndReady else { return }

            // Schedule a restore. This will do nothing unless we've never
            // registered a manifest before.
            self.restoreOrCreateManifestIfNecessary()

            // If we have any pending changes since we last launch, back them up now.
            self.backupPendingChanges()
        }
    }

    @objc private func willResignActive() {
        // If we have any pending changes, start a back up immediately
        // to try and make sure the service doesn't get stale. If for
        // some reason we aren't able to successfully complete this backup
        // while in the background we'll try again on the next app launch.
        backupPendingChanges()
    }

    // MARK: -

    @objc
    public func recordPendingDeletions(deletedIds: [AccountId]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        // Schedule a backup to run in the next ten seconds
        // if one hasn't been scheduled already.
        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        // Schedule a backup to run in the next ten seconds
        // if one hasn't been scheduled already.
        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedIds: [AccountId]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        // Schedule a backup to run in the next ten seconds
        // if one hasn't been scheduled already.
        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        // Schedule a backup to run in the next ten seconds
        // if one hasn't been scheduled already.
        scheduleBackupIfNecessary()
    }

    @objc
    public func backupPendingChanges() {
        let operation = StorageServiceOperation(mode: .backup)
        StorageServiceOperation.operationQueue.addOperation(operation)
    }

    @objc
    @discardableResult
    public func restoreOrCreateManifestIfNecessary() -> AnyPromise {
        let operation = StorageServiceOperation(mode: .restoreOrCreate)
        StorageServiceOperation.operationQueue.addOperation(operation)
        return AnyPromise(operation.promise)
    }

    // MARK: - Backup Scheduling

    private static var backupDebounceInterval: TimeInterval = kSecondInterval * 10
    private var backupTimer: Timer?

    // Schedule a one time backup. By default, this will happen ten
    // seconds after the first pending change is recorded.
    private func scheduleBackupIfNecessary() {
        DispatchQueue.main.async {
            // If we already have a backup scheduled, do nothing
            guard self.backupTimer == nil else { return }

            Logger.info("")

            self.backupTimer = Timer.scheduledTimer(
                timeInterval: StorageServiceManager.backupDebounceInterval,
                target: self,
                selector: #selector(self.backupTimerFired),
                userInfo: nil,
                repeats: false
            )
        }
    }

    @objc func backupTimerFired(_ timer: Timer) {
        AssertIsOnMainThread()

        Logger.info("")

        backupTimer?.invalidate()
        backupTimer = nil

        backupPendingChanges()
    }
}

// MARK: -

@objc(OWSStorageServiceOperation)
class StorageServiceOperation: OWSOperation {
    // MARK: - Dependencies

    private static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    private var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    public static var keyValueStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "kOWSStorageServiceOperation_IdentifierMap")
    }

    // MARK: -

    // We only ever want to be doing one storage operation at a time.
    // Pending updates queued up after a backup operation will not get
    // applied until the following backup. This allows us to be certain
    // when we do things like resolve conflicts that we're not going to
    // blow away any pending updates / deletions.
    fileprivate static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = logTag()
        return queue
    }()

    fileprivate enum Mode {
        case backup
        case restoreOrCreate
    }
    private let mode: Mode

    let promise: Promise<Void>
    private let resolver: Resolver<Void>

    fileprivate init(mode: Mode) {
        self.mode = mode
        (self.promise, self.resolver) = Promise<Void>.pending()
        super.init()
        self.remainingRetries = 4
    }

    // MARK: - Run

    override func didSucceed() {
        super.didSucceed()
        resolver.fulfill(())
    }

    override func didFail(error: Error) {
        super.didFail(error: error)
        resolver.reject(error)
    }

    // Called every retry, this is where the bulk of the operation's work should go.
    override public func run() {
        Logger.info("\(mode)")

        // Do nothing until the feature is enabled.
        guard FeatureFlags.socialGraphOnServer else {
            return reportSuccess()
        }

        // We don't have backup keys, do nothing. We'll try a
        // fresh restore once the keys are set.
        guard KeyBackupService.DerivedKey.storageService.isAvailable else {
            return reportSuccess()
        }

        switch mode {
        case .backup:
            backupPendingChanges()
        case .restoreOrCreate:
            restoreOrCreateManifestIfNecessary()
        }
    }

    // MARK: Mark Pending Changes

    fileprivate static func recordPendingUpdates(_ updatedAddresses: [SignalServiceAddress]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                let updatedIds = updatedAddresses.map { address in
                    OWSAccountIdFinder().ensureAccountId(forAddress: address, transaction: transaction)
                }

                recordPendingUpdates(updatedIds, transaction: transaction)
            }
        }
    }

    fileprivate static func recordPendingUpdates(_ updatedIds: [AccountId]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingUpdates(updatedIds, transaction: transaction)
            }
        }
    }

    private static func recordPendingUpdates(_ updatedIds: [AccountId], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var pendingChanges = StorageServiceOperation.accountChangeMap(transaction: transaction)

        for accountId in updatedIds {
            pendingChanges[accountId] = .updated
        }

        StorageServiceOperation.setAccountChangeMap(pendingChanges, transaction: transaction)
    }

    fileprivate static func recordPendingDeletions(_ deletedAddress: [SignalServiceAddress]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                let deletedIds = deletedAddress.map { address in
                    OWSAccountIdFinder().ensureAccountId(forAddress: address, transaction: transaction)
                }

                recordPendingDeletions(deletedIds, transaction: transaction)
            }
        }
    }

    fileprivate static func recordPendingDeletions(_ deletedIds: [AccountId]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingDeletions(deletedIds, transaction: transaction)
            }
        }
    }

    private static func recordPendingDeletions(_ deletedIds: [AccountId], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var pendingChanges = StorageServiceOperation.accountChangeMap(transaction: transaction)

        for accountId in deletedIds {
            pendingChanges[accountId] = .deleted
        }

        StorageServiceOperation.setAccountChangeMap(pendingChanges, transaction: transaction)
    }

    // MARK: Backup

    private func backupPendingChanges() {
        var pendingChanges: [AccountId: ChangeState] = [:]
        var identifierMap: BidirectionalDictionary<AccountId, StorageService.StorageIdentifier> = [:]
        var unknownIdentifiers: [StorageService.StorageIdentifier] = []
        var version: UInt64 = 0

        var updatedItems: [StorageService.StorageItem] = []
        var deletedIdentifiers: [StorageService.StorageIdentifier] = []

        databaseStorage.read { transaction in
            pendingChanges = StorageServiceOperation.accountChangeMap(transaction: transaction)
            identifierMap = StorageServiceOperation.accountToIdentifierMap(transaction: transaction)
            unknownIdentifiers = StorageServiceOperation.unknownIdentifiers(transaction: transaction)
            version = StorageServiceOperation.manifestVersion(transaction: transaction) ?? 0

            // Build an up-to-date storage item for every pending update
            updatedItems =
                pendingChanges.lazy.filter { $0.value == .updated }.compactMap { accountId, _ in
                    do {
                        // If there is an existing identifier for this contact,
                        // mark it for deletion. We generate a fresh identifer
                        // every time a contact record changes so other devices
                        // know which records have changes to fetch.
                        if let storageIdentifier = identifierMap[accountId] {
                            deletedIdentifiers.append(storageIdentifier)
                        }

                        // Generate a fresh identifier
                        let storageIdentifier = StorageService.StorageIdentifier.generate()
                        identifierMap[accountId] = storageIdentifier

                        let contactRecord = try StorageServiceProtoContactRecord.build(for: accountId, transaction: transaction)
                        let storageItem = try StorageService.StorageItem(identifier: storageIdentifier, contact: contactRecord)

                        // Clear pending changes
                        pendingChanges[accountId] = nil

                        return storageItem
                    } catch {
                        owsFailDebug("Unexpectedly failed to process changes for account \(error)")
                        // If for some reason we failed, we'll just skip it and try this account again next backup.
                        return nil
                    }
            }
        }

        // Lookup the identifier for every pending deletion
        deletedIdentifiers +=
            pendingChanges.lazy.filter { $0.value == .deleted }.compactMap { accountId, _ in
                // Clear the pending change
                pendingChanges[accountId] = nil

                guard let identifier = identifierMap[accountId] else {
                    // This contact doesn't exist in our records, it may have been
                    // added and then deleted before a backup occured. We can safely skip it.
                    return nil
                }

                // Remove this contact from the mapping
                identifierMap[accountId] = nil

                return identifier
        }

        // If we have no pending changes, we have nothing left to do
        guard !deletedIdentifiers.isEmpty || !updatedItems.isEmpty else {
            return reportSuccess()
        }

        // Bump the manifest version
        version += 1

        let manifestBuilder = StorageServiceProtoManifestRecord.builder(version: version)

        // We must persist any unknown identifiers, as they are potentially associated with
        // valid records that this version of the app doesn't yet understand how to parse.
        // Otherwise, this will cause ping-ponging with newer apps when they try and backup
        // new types of records, and then we subsequently delete them.
        manifestBuilder.setKeys(identifierMap.map { $1.data } + unknownIdentifiers.map { $0.data })

        let manifest: StorageServiceProtoManifestRecord
        do {
            manifest = try manifestBuilder.build()
        } catch {
            return reportError(OWSAssertionError("failed to build proto"))
        }

        StorageService.updateManifest(
            manifest,
            newItems: updatedItems,
            deletedIdentifiers: deletedIdentifiers
        ).done(on: .global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                // Successfuly updated, store our changes.
                self.databaseStorage.write { transaction in
                    StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
                    StorageServiceOperation.setAccountChangeMap(pendingChanges, transaction: transaction)
                    StorageServiceOperation.setManifestVersion(version, transaction: transaction)
                    StorageServiceOperation.setAccountToIdentifierMap(identifierMap, transaction: transaction)
                }

                // Notify our other devices that the storage manifest has changed.
                OWSSyncManager.shared().sendFetchLatestStorageManifestSyncMessage()

                return self.reportSuccess()
            }

            // Throw away all our work, resolve conflicts, and try again.
            self.mergeLocalManifest(withRemoteManifest: conflictingManifest, backupAfterSuccess: true)
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }.retainUntilComplete()
    }

    // MARK: Restore

    private func restoreOrCreateManifestIfNecessary() {
        var manifestVersion: UInt64?
        databaseStorage.read { transaction in
            manifestVersion = StorageServiceOperation.manifestVersion(transaction: transaction)
        }

        StorageService.fetchManifest().done(on: .global()) { manifest in
            guard let manifest = manifest else {
                // There is no existing manifest, lets create one with all our contacts.
                return self.createNewManifest(version: 1)
            }

            guard manifest.version != manifestVersion else {
                // Our manifest version matches the server version, nothing to do here.
                return self.reportSuccess()
            }

            // Our manifest is not the latest, merge in the latest copy.
            self.mergeLocalManifest(withRemoteManifest: manifest, backupAfterSuccess: false)

        }.catch { error in
            if let storageError = error as? StorageService.StorageError {

                // If we succeeded to fetch the manifest but were unable to decrypt it,
                // it likely means our keys changed.
                if case .decryptionFailed(let previousManifestVersion) = storageError {
                    // If this is the primary device, throw everything away and re-encrypt
                    // the social graph with the keys we have locally.
                    if TSAccountManager.sharedInstance().isPrimaryDevice {
                        return self.createNewManifest(version: previousManifestVersion + 1)
                    }

                    // If this is a linked device, give up and request the latest storage
                    // service key from the primary device.
                    self.databaseStorage.asyncWrite { transaction in
                        // Clear out the key, it's no longer valid. This will prevent us
                        // from trying to backup again until the sync response is received.
                        KeyBackupService.storeSyncedKey(type: .storageService, data: nil, transaction: transaction)
                        OWSSyncManager.shared().sendKeysSyncRequestMessage(transaction: transaction)
                    }
                }

                return self.reportError(storageError)
            }

            self.reportError(OWSAssertionError("received unexpected error when fetching manifest"))
        }.retainUntilComplete()
    }

    private func createNewManifest(version: UInt64) {
        var allItems: [StorageService.StorageItem] = []
        var identifierMap: BidirectionalDictionary<AccountId, StorageService.StorageIdentifier> = [:]

        databaseStorage.read { transaction in
            SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                if recipient.devices.count > 0 {
                    let identifier = StorageService.StorageIdentifier.generate()
                    identifierMap[recipient.accountId] = identifier

                    do {
                        let contactRecord = try StorageServiceProtoContactRecord.build(for: recipient.accountId, transaction: transaction)
                        allItems.append(
                            try .init(identifier: identifier, contact: contactRecord)
                        )
                    } catch {
                        // We'll just skip it, something may be wrong with our local data.
                        // We'll try and backup this contact again when something changes.
                        owsFailDebug("unexpectedly failed to build contact record")
                    }
                }
            }
        }

        let manifestBuilder = StorageServiceProtoManifestRecord.builder(version: version)
        manifestBuilder.setKeys(allItems.map { $0.identifier.data })

        let manifest: StorageServiceProtoManifestRecord
        do {
            manifest = try manifestBuilder.build()
        } catch {
            return reportError(OWSAssertionError("failed to build proto"))
        }

        StorageService.updateManifest(
            manifest,
            newItems: allItems,
            deletedIdentifiers: []
        ).done(on: .global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                // Successfuly updated, store our changes.
                self.databaseStorage.write { transaction in
                    StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
                    StorageServiceOperation.setAccountChangeMap([:], transaction: transaction)
                    StorageServiceOperation.setUnknownIdentifiersTypeMap([:], transaction: transaction)
                    StorageServiceOperation.setManifestVersion(version, transaction: transaction)
                    StorageServiceOperation.setAccountToIdentifierMap(identifierMap, transaction: transaction)
                }

                return self.reportSuccess()
            }

            // We got a conflicting manifest that we were able to decrypt, so we may not need
            // to recreate our manifest after all. Throw away all our work, resolve conflicts,
            // and try again.
            self.mergeLocalManifest(withRemoteManifest: conflictingManifest, backupAfterSuccess: true)
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }.retainUntilComplete()
    }

    // MARK: - Conflict Resolution

    private func mergeLocalManifest(withRemoteManifest manifest: StorageServiceProtoManifestRecord, backupAfterSuccess: Bool) {
        var identifierMap: BidirectionalDictionary<AccountId, StorageService.StorageIdentifier> = [:]
        var unknownIdentifiersTypeMap: [UInt32: [StorageService.StorageIdentifier]] = [:]
        var pendingChanges: [AccountId: ChangeState] = [:]
        var consecutiveConflicts = 0

        databaseStorage.write { transaction in
            identifierMap = StorageServiceOperation.accountToIdentifierMap(transaction: transaction)
            unknownIdentifiersTypeMap = StorageServiceOperation.unknownIdentifiersTypeMap(transaction: transaction)
            pendingChanges = StorageServiceOperation.accountChangeMap(transaction: transaction)

            // Increment our conflict count.
            consecutiveConflicts = StorageServiceOperation.consecutiveConflicts(transaction: transaction)
            consecutiveConflicts += 1
            StorageServiceOperation.setConsecutiveConflicts(consecutiveConflicts, transaction: transaction)
        }

        // If we've tried many times in a row to resolve conflicts, something weird is happening
        // (potentially a bug on the service or a race with another app). Give up and wait until
        // the next backup runs.
        guard consecutiveConflicts <= StorageServiceOperation.maxConsecutiveConflicts else {
            owsFailDebug("unexpectedly have had numerous repeated conflicts")

            // Clear out the consecutive conflicts count so we can try again later.
            databaseStorage.write { transaction in
                StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
            }

            return reportError(OWSAssertionError("exceeded max consectuive conflicts, creating a new manifest"))
        }

        // Calculate new or updated items by looking up the ids
        // of any items we don't know about locally. Since a new
        // id is always generated after a change, this should always
        // reflect the only items we need to fetch from the service.
        let allManifestItems: Set<StorageService.StorageIdentifier> = Set(manifest.keys.map { .init(data: $0) })

        // Cleanup our unknown identifiers type map to only reflect
        // identifiers that still exist in the manifest.
        unknownIdentifiersTypeMap = unknownIdentifiersTypeMap.mapValues { Array(allManifestItems.intersection($0)) }

        // We ignore any items of unknown type, because there is no
        // point in trying to fetch these items again. A newer app
        // version will clear out the identifiers once the type
        // becomes known and re-process those items.
        let newOrUpdatedItems = Array(allManifestItems.subtracting(identifierMap.backwardKeys).subtracting(unknownIdentifiersTypeMap.flatMap { $0.value }))

        // Fetch all the items in the new manifest and resolve any conflicts appropriately.
        StorageService.fetchItems(for: newOrUpdatedItems).done(on: .global()) { items in
            self.databaseStorage.write { transaction in
                for item in items {
                    guard let contactRecord = item.contactRecord else {
                        // This is not a contact record. We don't know about any other kinds of records yet,
                        // so record this identifier in our unknown mapping. This allows us to skip fetching
                        // it in the future and not accidentally blow it away when we push an update.
                        var unknownIdentifiersOfType = unknownIdentifiersTypeMap[item.record.type] ?? []
                        unknownIdentifiersOfType.append(item.identifier)
                        unknownIdentifiersTypeMap[item.record.type] = unknownIdentifiersOfType
                        continue
                    }

                    switch contactRecord.mergeWithLocalContact(transaction: transaction) {
                    case .invalid:
                        // This contact record was invalid, ignore it.
                        // we'll clear it out in the next backup.
                        break

                    case .needsUpdate(let accountId):
                        // our local version was newer, flag this account as needing a sync
                        pendingChanges[accountId] = .updated

                        // update the mapping
                        identifierMap[accountId] = item.identifier

                    case .resolved(let accountId):
                        // update the mapping
                        identifierMap[accountId] = item.identifier
                    }
                }

                StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
                StorageServiceOperation.setAccountChangeMap(pendingChanges, transaction: transaction)
                StorageServiceOperation.setManifestVersion(manifest.version, transaction: transaction)
                StorageServiceOperation.setAccountToIdentifierMap(identifierMap, transaction: transaction)
                StorageServiceOperation.setUnknownIdentifiersTypeMap(unknownIdentifiersTypeMap, transaction: transaction)

                if backupAfterSuccess { StorageServiceManager.shared.backupPendingChanges() }

                self.reportSuccess()
            }
        }.catch { error in
            if let storageError = error as? StorageService.StorageError {
                return self.reportError(storageError)
            }

            self.reportError(OWSAssertionError("received unexpected error when fetching items"))
        }.retainUntilComplete()
    }

    // MARK: - Accessors

    private static let accountToIdentifierMapKey = "accountToIdentifierMap"
    private static let unknownIdentifierTypeMapKey = "unknownIdentifierTypeMapKey"
    private static let accountChangeMapKey = "accountChangeMap"
    private static let manifestVersionKey = "manifestVersion"
    private static let consecutiveConflictsKey = "consecutiveConflicts"

    private static func manifestVersion(transaction: SDSAnyReadTransaction) -> UInt64? {
        return keyValueStore.getUInt64(manifestVersionKey, transaction: transaction)
    }

    private static func setManifestVersion( _ verison: UInt64, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setUInt64(verison, key: manifestVersionKey, transaction: transaction)
    }

    private static func accountToIdentifierMap(transaction: SDSAnyReadTransaction) -> BidirectionalDictionary<AccountId, StorageService.StorageIdentifier> {
        guard let anyDictionary = keyValueStore.getObject(accountToIdentifierMapKey, transaction: transaction) as? AnyBidirectionalDictionary,
            let dictionary = BidirectionalDictionary<AccountId, Data>(anyDictionary) else {
            return [:]
        }
        return dictionary.mapValues { .init(data: $0) }
    }

    private static func setAccountToIdentifierMap( _ dictionary: BidirectionalDictionary<AccountId, StorageService.StorageIdentifier>, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setObject(
            AnyBidirectionalDictionary(dictionary.mapValues { $0.data }),
            key: accountToIdentifierMapKey,
            transaction: transaction
        )
    }

    private static func unknownIdentifiers(transaction: SDSAnyReadTransaction) -> [StorageService.StorageIdentifier] {
        return unknownIdentifiersTypeMap(transaction: transaction).flatMap { $0.value }
    }

    private static func unknownIdentifiersTypeMap(transaction: SDSAnyReadTransaction) -> [UInt32: [StorageService.StorageIdentifier]] {
        guard let unknownIdentifiers = keyValueStore.getObject(unknownIdentifierTypeMapKey, transaction: transaction) as? [UInt32: [Data]] else { return [:] }
        return unknownIdentifiers.mapValues { $0.map { .init(data: $0) } }
    }

    private static func setUnknownIdentifiersTypeMap( _ dictionary: [UInt32: [StorageService.StorageIdentifier]], transaction: SDSAnyWriteTransaction) {
        keyValueStore.setObject(
            dictionary.mapValues { $0.map { $0.data }},
            key: unknownIdentifierTypeMapKey,
            transaction: transaction
        )
    }

    private enum ChangeState: Int {
        case unchanged = 0
        case updated = 1
        case deleted = 2
    }
    private static func accountChangeMap(transaction: SDSAnyReadTransaction) -> [AccountId: ChangeState] {
        let accountIdToIdentifierData = keyValueStore.getObject(accountChangeMapKey, transaction: transaction) as? [AccountId: Int] ?? [:]
        return accountIdToIdentifierData.compactMapValues { ChangeState(rawValue: $0) }
    }

    private static func setAccountChangeMap(_ map: [AccountId: ChangeState], transaction: SDSAnyWriteTransaction) {
        keyValueStore.setObject(map.mapValues { $0.rawValue }, key: accountChangeMapKey, transaction: transaction)
    }

    private static var maxConsecutiveConflicts = 3

    private static func consecutiveConflicts(transaction: SDSAnyReadTransaction) -> Int {
        return keyValueStore.getInt(consecutiveConflictsKey, transaction: transaction) ?? 0
    }

    private static func setConsecutiveConflicts( _ consecutiveConflicts: Int, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setInt(consecutiveConflicts, key: consecutiveConflictsKey, transaction: transaction)
    }
}
