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

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedGroupIds: [Data]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedGroupIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedIds: [AccountId]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedGroupIds: [Data]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedGroupIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

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

    @objc
    public func resetLocalData(transaction: SDSAnyWriteTransaction) {
        Logger.info("Reseting local storage service data.")
        StorageServiceOperation.keyValueStore.removeAll(transaction: transaction)
    }

    // MARK: - Backup Scheduling

    private static var backupDebounceInterval: TimeInterval = 0.2
    private var backupTimer: Timer?

    // Schedule a one time backup. By default, this will happen `backupDebounceInterval`
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

    override var description: String {
        return "StorageServiceOperation.\(mode)"
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

        // Don't do anything unless storage service is enabled on the server.
        // This is a kill switch in case something goes wrong.
        // TODO: Derive Storage Service Key – When we start using the master
        // key to derive the storage service key we cannot rely on this since
        // we will need to do storage service operations during registration.
        guard RemoteConfig.storageService else {
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

    fileprivate static func recordPendingUpdates(_ updatedGroupIds: [Data]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingUpdates(updatedGroupIds, transaction: transaction)
            }
        }
    }

    private static func recordPendingUpdates(_ updatedGroupIds: [Data], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var pendingChanges = StorageServiceOperation.groupIdChangeMap(transaction: transaction)

        for groupId in updatedGroupIds {
            pendingChanges[groupId] = .updated
        }

        StorageServiceOperation.setGroupIdChangeMap(pendingChanges, transaction: transaction)
    }

    fileprivate static func recordPendingDeletions(_ deletedGroupIds: [Data]) -> Operation {
         return BlockOperation {
             databaseStorage.write { transaction in
                 recordPendingDeletions(deletedGroupIds, transaction: transaction)
             }
         }
     }

     private static func recordPendingDeletions(_ deletedGroupIds: [Data], transaction: SDSAnyWriteTransaction) {
         Logger.info("")

         var pendingChanges = StorageServiceOperation.groupIdChangeMap(transaction: transaction)

         for groupId in deletedGroupIds {
             pendingChanges[groupId] = .deleted
         }

         StorageServiceOperation.setGroupIdChangeMap(pendingChanges, transaction: transaction)
     }

    // MARK: Backup

    private func backupPendingChanges() {
        var pendingAccountChanges: [AccountId: ChangeState] = [:]
        var accountIdentifierMap: BidirectionalDictionary<AccountId, StorageService.StorageIdentifier> = [:]
        var pendingGroupChanges: [Data: ChangeState] = [:]
        var groupIdentifierMap: BidirectionalDictionary<Data, StorageService.StorageIdentifier> = [:]
        var unknownIdentifiers: [StorageService.StorageIdentifier] = []
        var version: UInt64 = 0

        var updatedItems: [StorageService.StorageItem] = []
        var deletedIdentifiers: [StorageService.StorageIdentifier] = []

        databaseStorage.read { transaction in
            pendingAccountChanges = StorageServiceOperation.accountChangeMap(transaction: transaction)
            accountIdentifierMap = StorageServiceOperation.accountToIdentifierMap(transaction: transaction)
            pendingGroupChanges = StorageServiceOperation.groupIdChangeMap(transaction: transaction)
            groupIdentifierMap = StorageServiceOperation.groupIdToIdentifierMap(transaction: transaction)
            unknownIdentifiers = StorageServiceOperation.unknownIdentifiers(transaction: transaction)
            version = StorageServiceOperation.manifestVersion(transaction: transaction) ?? 0

            // Build an up-to-date storage item for every pending account update
            updatedItems =
                pendingAccountChanges.lazy.filter { $0.value == .updated }.compactMap { accountId, _ in
                    do {
                        // If there is an existing identifier for this contact,
                        // mark it for deletion. We generate a fresh identifer
                        // every time a contact record changes so other devices
                        // know which records have changes to fetch.
                        if let storageIdentifier = accountIdentifierMap[accountId] {
                            deletedIdentifiers.append(storageIdentifier)
                        }

                        // Generate a fresh identifier
                        let storageIdentifier = StorageService.StorageIdentifier.generate()
                        accountIdentifierMap[accountId] = storageIdentifier

                        let contactRecord = try StorageServiceProtoContactRecord.build(for: accountId, transaction: transaction)
                        let storageItem = try StorageService.StorageItem(identifier: storageIdentifier, contact: contactRecord)

                        // Clear pending changes
                        pendingAccountChanges[accountId] = nil

                        return storageItem
                    } catch {
                        // If the accountId we're trying to backup is no longer associated with
                        // any known address, we no longer need to care about it. It's possible
                        // that account was unregistered / the SignalRecipient no longer exists.
                        if case StorageService.StorageError.accountMissing = error {
                            Logger.info("Clearing data for missing accountId \(accountId).")

                            accountIdentifierMap[accountId] = nil
                            pendingAccountChanges[accountId] = nil
                        } else {
                            // If for some reason we failed, we'll just skip it and try this account again next backup.
                            owsFailDebug("Unexpectedly failed to process changes for account \(error)")
                        }

                        return nil
                    }
            }

            // Build an up-to-date storage item for every pending group update
            updatedItems +=
                pendingGroupChanges.lazy.filter { $0.value == .updated }.compactMap { groupId, _ in
                    do {
                        // If there is an existing identifier for this group,
                        // mark it for deletion. We generate a fresh identifer
                        // every time a contact record changes so other devices
                        // know which records have changes to fetch.
                        if let storageIdentifier = groupIdentifierMap[groupId] {
                            deletedIdentifiers.append(storageIdentifier)
                        }

                        // Generate a fresh identifier
                        let storageIdentifier = StorageService.StorageIdentifier.generate()
                        groupIdentifierMap[groupId] = storageIdentifier

                        let groupV1Record = try StorageServiceProtoGroupV1Record.build(for: groupId, transaction: transaction)
                        let storageItem = try StorageService.StorageItem(identifier: storageIdentifier, groupV1: groupV1Record)

                        // Clear pending changes
                        pendingGroupChanges[groupId] = nil

                        return storageItem
                    } catch {
                        owsFailDebug("Unexpectedly failed to process changes for account \(error)")
                        // If for some reason we failed, we'll just skip it and try this account again next backup.
                        return nil
                    }
            }
        }

        // Lookup the identifier for every pending account deletion
        deletedIdentifiers +=
            pendingAccountChanges.lazy.filter { $0.value == .deleted }.compactMap { accountId, _ in
                // Clear the pending change
                pendingAccountChanges[accountId] = nil

                guard let identifier = accountIdentifierMap[accountId] else {
                    // This contact doesn't exist in our records, it may have been
                    // added and then deleted before a backup occured. We can safely skip it.
                    return nil
                }

                // Remove this contact from the mapping
                accountIdentifierMap[accountId] = nil

                return identifier
        }

        // Lookup the identifier for every pending group deletion
        deletedIdentifiers +=
            pendingGroupChanges.lazy.filter { $0.value == .deleted }.compactMap { groupId, _ in
                // Clear the pending change
                pendingGroupChanges[groupId] = nil

                guard let identifier = groupIdentifierMap[groupId] else {
                    // This group doesn't exist in our records, it may have been
                    // added and then deleted before a backup occured. We can safely skip it.
                    return nil
                }

                // Remove this group from the mapping
                groupIdentifierMap[groupId] = nil

                return identifier
        }

        // If we have no pending changes, we have nothing left to do
        guard !deletedIdentifiers.isEmpty || !updatedItems.isEmpty else {
            return reportSuccess()
        }

        // Bump the manifest version
        version += 1

        let manifestBuilder = StorageServiceProtoManifestRecord.builder(version: version)

        let allKeys = accountIdentifierMap.map { $1.data } +
            groupIdentifierMap.map { $1.data } +
            unknownIdentifiers.map { $0.data }

        // We must persist any unknown identifiers, as they are potentially associated with
        // valid records that this version of the app doesn't yet understand how to parse.
        // Otherwise, this will cause ping-ponging with newer apps when they try and backup
        // new types of records, and then we subsequently delete them.
        manifestBuilder.setKeys(allKeys)

        let manifest: StorageServiceProtoManifestRecord
        do {
            manifest = try manifestBuilder.build()
        } catch {
            return reportError(OWSAssertionError("failed to build proto with error: \(error)"))
        }

        Logger.info("Backing up pending changes with manifest version: \(version). \(updatedItems.count) new items. \(deletedIdentifiers.count) deleted items. Total keys: \(allKeys.count)")

        StorageService.updateManifest(
            manifest,
            newItems: updatedItems,
            deletedIdentifiers: deletedIdentifiers
        ).done(on: .global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                Logger.info("Successfully updated to manifest version: \(version)")

                // Successfuly updated, store our changes.
                self.databaseStorage.write { transaction in
                    StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
                    StorageServiceOperation.setAccountChangeMap(pendingAccountChanges, transaction: transaction)
                    StorageServiceOperation.setGroupIdChangeMap(pendingGroupChanges, transaction: transaction)
                    StorageServiceOperation.setManifestVersion(version, transaction: transaction)
                    StorageServiceOperation.setAccountToIdentifierMap(accountIdentifierMap, transaction: transaction)
                    StorageServiceOperation.setGroupIdToIdentifierMap(groupIdentifierMap, transaction: transaction)
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

        StorageService.fetchLatestManifest(greaterThanVersion: manifestVersion).done(on: .global()) { response in
            switch response {
            case .noExistingManifest:
                // There is no existing manifest, lets create one.
                return self.createNewManifest(version: 1)
            case .noNewerManifest:
                // Our manifest version matches the server version, nothing to do here.
                return self.reportSuccess()
            case .latestManifest(let manifest):
                // Our manifest is not the latest, merge in the latest copy.
                self.mergeLocalManifest(withRemoteManifest: manifest, backupAfterSuccess: false)
            }
        }.catch { error in
            if let storageError = error as? StorageService.StorageError {

                // If we succeeded to fetch the manifest but were unable to decrypt it,
                // it likely means our keys changed.
                if case .manifestDecryptionFailed(let previousManifestVersion) = storageError {
                    // If this is the primary device, throw everything away and re-encrypt
                    // the social graph with the keys we have locally.
                    if TSAccountManager.sharedInstance().isPrimaryDevice {
                        Logger.info("Manifest decryption failed, recreating manifest.")
                        return self.createNewManifest(version: previousManifestVersion + 1)
                    }

                    Logger.info("Manifest decryption failed, clearing storage service keys.")

                    // If this is a linked device, give up and request the latest storage
                    // service key from the primary device.
                    self.databaseStorage.write { transaction in
                        // Clear out the key, it's no longer valid. This will prevent us
                        // from trying to backup again until the sync response is received.
                        KeyBackupService.storeSyncedKey(type: .storageService, data: nil, transaction: transaction)
                        OWSSyncManager.shared().sendKeysSyncRequestMessage(transaction: transaction)
                    }
                }

                return self.reportError(storageError)
            }

            self.reportError(withUndefinedRetry: error)
        }.retainUntilComplete()
    }

    private func createNewManifest(version: UInt64) {
        var allItems: [StorageService.StorageItem] = []
        var accountIdentifierMap: BidirectionalDictionary<AccountId, StorageService.StorageIdentifier> = [:]
        var groupIdentifierMap: BidirectionalDictionary<Data, StorageService.StorageIdentifier> = [:]

        databaseStorage.read { transaction in
            SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                if recipient.devices.count > 0 {
                    let identifier = StorageService.StorageIdentifier.generate()
                    accountIdentifierMap[recipient.accountId] = identifier

                    do {
                        let contactRecord = try StorageServiceProtoContactRecord.build(for: recipient.accountId, transaction: transaction)
                        allItems.append(
                            try .init(identifier: identifier, contact: contactRecord)
                        )
                    } catch {
                        // We'll just skip it, something may be wrong with our local data.
                        // We'll try and backup this contact again when something changes.
                        owsFailDebug("failed to build contact record with error: \(error)")
                    }
                }
            }

            TSGroupThread.anyEnumerate(transaction: transaction) { thread, _ in
                guard let groupThread = thread as? TSGroupThread else { return }

                // TODO: Support v2 groups
                guard case .V1 = groupThread.groupModel.groupsVersion else { return }

                let groupId = groupThread.groupModel.groupId
                let identifier = StorageService.StorageIdentifier.generate()
                groupIdentifierMap[groupId] = identifier

                do {
                    let groupV1Record = try StorageServiceProtoGroupV1Record.build(for: groupId, transaction: transaction)
                    allItems.append(
                        try .init(identifier: identifier, groupV1: groupV1Record)
                    )
                } catch {
                    // We'll just skip it, something may be wrong with our local data.
                    // We'll try and backup this group again when something changes.
                    owsFailDebug("failed to build group record with error: \(error)")
                }
            }
        }

        let manifestBuilder = StorageServiceProtoManifestRecord.builder(version: version)
        manifestBuilder.setKeys(allItems.map { $0.identifier.data })

        let manifest: StorageServiceProtoManifestRecord
        do {
            manifest = try manifestBuilder.build()
        } catch {
            return reportError(OWSAssertionError("failed to build proto with error: \(error)"))
        }

        Logger.info("Creating a new manifest with manifest version: \(version). Total keys: \(allItems.count)")

        // We want to do this only when absolutely necessarry as it's an expensive
        // query on the server. When we set this flag, the server will query an
        // purge and orphan records.
        let shouldDeletePreviousRecords = version > 1

        StorageService.updateManifest(
            manifest,
            newItems: allItems,
            deleteAllExistingRecords: shouldDeletePreviousRecords
        ).done(on: .global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                // Successfuly updated, store our changes.
                self.databaseStorage.write { transaction in
                    StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
                    StorageServiceOperation.setAccountChangeMap([:], transaction: transaction)
                    StorageServiceOperation.setGroupIdChangeMap([:], transaction: transaction)
                    StorageServiceOperation.setUnknownIdentifiersTypeMap([:], transaction: transaction)
                    StorageServiceOperation.setManifestVersion(version, transaction: transaction)
                    StorageServiceOperation.setAccountToIdentifierMap(accountIdentifierMap, transaction: transaction)
                    StorageServiceOperation.setGroupIdToIdentifierMap(groupIdentifierMap, transaction: transaction)
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
        var accountIdentifierMap: BidirectionalDictionary<AccountId, StorageService.StorageIdentifier> = [:]
        var groupIdentifierMap: BidirectionalDictionary<Data, StorageService.StorageIdentifier> = [:]
        var unknownIdentifiersTypeMap: [UInt32: [StorageService.StorageIdentifier]] = [:]
        var pendingAccountChanges: [AccountId: ChangeState] = [:]
        var pendingGroupChanges: [Data: ChangeState] = [:]
        var consecutiveConflicts = 0

        databaseStorage.write { transaction in
            accountIdentifierMap = StorageServiceOperation.accountToIdentifierMap(transaction: transaction)
            groupIdentifierMap = StorageServiceOperation.groupIdToIdentifierMap(transaction: transaction)
            unknownIdentifiersTypeMap = StorageServiceOperation.unknownIdentifiersTypeMap(transaction: transaction)
            pendingAccountChanges = StorageServiceOperation.accountChangeMap(transaction: transaction)
            pendingGroupChanges = StorageServiceOperation.groupIdChangeMap(transaction: transaction)

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

        let localKeysCount = accountIdentifierMap.count + groupIdentifierMap.count + unknownIdentifiersTypeMap.flatMap { $0.value }.count

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
        let newOrUpdatedItems = Array(
            allManifestItems
                .subtracting(accountIdentifierMap.backwardKeys)
                .subtracting(groupIdentifierMap.backwardKeys)
                .subtracting(unknownIdentifiersTypeMap.flatMap { $0.value })
        )

        Logger.info("Merging with newer remote manifest version: \(manifest.version). \(newOrUpdatedItems.count) new or updated items. Remote key count: \(allManifestItems.count). Local key count: \(localKeysCount).")

        // Fetch all the items in the new manifest and resolve any conflicts appropriately.
        StorageService.fetchItems(for: newOrUpdatedItems).done(on: .global()) { items in
            self.databaseStorage.write { transaction in
                for item in items {
                    if let contactRecord = item.contactRecord {
                        switch contactRecord.mergeWithLocalContact(transaction: transaction) {
                        case .invalid:
                            // This contact record was invalid, ignore it.
                            // we'll clear it out in the next backup.
                            break

                        case .needsUpdate(let accountId):
                            // our local version was newer, flag this account as needing a sync
                            pendingAccountChanges[accountId] = .updated

                            // update the mapping
                            accountIdentifierMap[accountId] = item.identifier

                        case .resolved(let accountId):
                            // We're all resolved, so if we had a pending change for this contact clear it out.
                            pendingAccountChanges[accountId] = nil

                            // update the mapping
                            accountIdentifierMap[accountId] = item.identifier
                        }
                    } else if let groupV1Record = item.groupV1Record {
                        switch groupV1Record.mergeWithLocalGroup(transaction: transaction) {
                        case .invalid:
                            // This record was invalid, ignore it.
                            // we'll clear it out in the next backup.
                            break

                        case .needsUpdate(let groupId):
                            // our local version was newer, flag this account as needing a sync
                            pendingGroupChanges[groupId] = .updated

                            // update the mapping
                            groupIdentifierMap[groupId] = item.identifier

                        case .resolved(let groupId):
                            // We're all resolved, so if we had a pending change for this group clear it out.
                            pendingGroupChanges[groupId] = nil

                            // update the mapping
                            groupIdentifierMap[groupId] = item.identifier
                        }
                    } else {
                        // This is not a record type we know about yet, so record this identifier in
                        // our unknown mapping. This allows us to skip fetching it in the future and
                        // not accidentally blow it away when we push an update.
                        var unknownIdentifiersOfType = unknownIdentifiersTypeMap[item.record.type] ?? []
                        unknownIdentifiersOfType.append(item.identifier)
                        unknownIdentifiersTypeMap[item.record.type] = unknownIdentifiersOfType
                        continue
                    }

                }

                // Mark any orphaned records as pending update so we re-add them to the manifest.

                var orphanedGroupCount = 0
                Set(groupIdentifierMap.backwardKeys).subtracting(allManifestItems).forEach { identifier in
                    if let groupId = groupIdentifierMap[identifier] { pendingGroupChanges[groupId] = .updated }
                    orphanedGroupCount += 1
                }

                var orphanedAccountCount = 0
                Set(accountIdentifierMap.backwardKeys).subtracting(allManifestItems).forEach { identifier in
                    if let accountId = accountIdentifierMap[identifier] { pendingAccountChanges[accountId] = .updated }
                    orphanedAccountCount += 1
                }

                Logger.info("Successfully merged with remote manifest version: \(manifest.version). \(pendingAccountChanges.count + pendingGroupChanges.count) pending updates remaining including \(orphanedAccountCount) orphaned accounts and \(orphanedGroupCount) orphaned groups.")

                StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
                StorageServiceOperation.setAccountChangeMap(pendingAccountChanges, transaction: transaction)
                StorageServiceOperation.setGroupIdChangeMap(pendingGroupChanges, transaction: transaction)
                StorageServiceOperation.setManifestVersion(manifest.version, transaction: transaction)
                StorageServiceOperation.setAccountToIdentifierMap(accountIdentifierMap, transaction: transaction)
                StorageServiceOperation.setGroupIdToIdentifierMap(groupIdentifierMap, transaction: transaction)
                StorageServiceOperation.setUnknownIdentifiersTypeMap(unknownIdentifiersTypeMap, transaction: transaction)

                if backupAfterSuccess { StorageServiceManager.shared.backupPendingChanges() }

                self.reportSuccess()
            }
        }.catch { error in
            if let storageError = error as? StorageService.StorageError {

                // If we succeeded to fetch the records but were unable to decrypt any of them,
                // it likely means our keys changed.
                if case .itemDecryptionFailed = storageError {
                    // If this is the primary device, throw everything away and re-encrypt
                    // the social graph with the keys we have locally.
                    if TSAccountManager.sharedInstance().isPrimaryDevice {
                        Logger.info("Item decryption failed, recreating manifest.")
                        return self.createNewManifest(version: manifest.version + 1)
                    }

                    Logger.info("Item decryption failed, clearing storage service keys.")

                    // If this is a linked device, give up and request the latest storage
                    // service key from the primary device.
                    self.databaseStorage.write { transaction in
                        // Clear out the key, it's no longer valid. This will prevent us
                        // from trying to backup again until the sync response is received.
                        KeyBackupService.storeSyncedKey(type: .storageService, data: nil, transaction: transaction)
                        OWSSyncManager.shared().sendKeysSyncRequestMessage(transaction: transaction)
                    }
                }

                return self.reportError(storageError)
            }

            self.reportError(withUndefinedRetry: error)
        }.retainUntilComplete()
    }

    // MARK: - Accessors

    private static let accountToIdentifierMapKey = "accountToIdentifierMap"
    private static let groupIdToIdentifierMapKey = "groupIdToIdentifierMap"
    private static let unknownIdentifierTypeMapKey = "unknownIdentifierTypeMapKey"
    private static let accountChangeMapKey = "accountChangeMap"
    private static let groupIdChangeMapKey = "groupIdChangeMap"
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

    private static func groupIdToIdentifierMap(transaction: SDSAnyReadTransaction) -> BidirectionalDictionary<Data, StorageService.StorageIdentifier> {
        guard let anyDictionary = keyValueStore.getObject(groupIdToIdentifierMapKey, transaction: transaction) as? AnyBidirectionalDictionary,
            let dictionary = BidirectionalDictionary<Data, Data>(anyDictionary) else {
            return [:]
        }
        return dictionary.mapValues { .init(data: $0) }
    }

    private static func setGroupIdToIdentifierMap( _ dictionary: BidirectionalDictionary<Data, StorageService.StorageIdentifier>, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setObject(
            AnyBidirectionalDictionary(dictionary.mapValues { $0.data }),
            key: groupIdToIdentifierMapKey,
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

    private static func groupIdChangeMap(transaction: SDSAnyReadTransaction) -> [Data: ChangeState] {
        let accountIdToIdentifierData = keyValueStore.getObject(groupIdChangeMapKey, transaction: transaction) as? [Data: Int] ?? [:]
        return accountIdToIdentifierData.compactMapValues { ChangeState(rawValue: $0) }
    }

    private static func setGroupIdChangeMap(_ map: [Data: ChangeState], transaction: SDSAnyWriteTransaction) {
        keyValueStore.setObject(map.mapValues { $0.rawValue }, key: groupIdChangeMapKey, transaction: transaction)
    }

    private static var maxConsecutiveConflicts = 3

    private static func consecutiveConflicts(transaction: SDSAnyReadTransaction) -> Int {
        return keyValueStore.getInt(consecutiveConflictsKey, transaction: transaction) ?? 0
    }

    private static func setConsecutiveConflicts( _ consecutiveConflicts: Int, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setInt(consecutiveConflicts, key: consecutiveConflictsKey, transaction: transaction)
    }
}
