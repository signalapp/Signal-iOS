//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSStorageServiceManager)
public class StorageServiceManager: NSObject, StorageServiceManagerProtocol {

    @objc
    public static let shared = StorageServiceManager()

    // MARK: - Dependencies

    var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.cleanUpUnknownIdentifiers()
        }

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.willResignActive),
                name: .OWSApplicationWillResignActive,
                object: nil
            )
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
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
    public func recordPendingDeletions(deletedAccountIds: [AccountId]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedAccountIds: deletedAccountIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedAddresses: deletedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedGroupV1Ids: [Data]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedGroupV1Ids: deletedGroupV1Ids)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedGroupV2MasterKeys: [Data]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedGroupV2MasterKeys: deletedGroupV2MasterKeys)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedAccountIds: [AccountId]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedAccountIds: updatedAccountIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedAddresses: updatedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedGroupV1Ids: [Data]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedGroupV1Ids: updatedGroupV1Ids)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedGroupV2MasterKeys: updatedGroupV2MasterKeys)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(groupModel: TSGroupModel) {
        if let groupModelV2 = groupModel as? TSGroupModelV2 {
            let masterKeyData: Data
            do {
                masterKeyData = try groupsV2.masterKeyData(forGroupModel: groupModelV2)
            } catch {
                owsFailDebug("Missing master key: \(error)")
                return
            }
            guard groupsV2.isValidGroupV2MasterKey(masterKeyData) else {
                owsFailDebug("Invalid master key.")
                return
            }

            recordPendingUpdates(updatedGroupV2MasterKeys: [ masterKeyData ])
        } else {
            recordPendingUpdates(updatedGroupV1Ids: [ groupModel.groupId ])
        }
    }

    public func recordPendingLocalAccountUpdates() {
        let operation = StorageServiceOperation.recordPendingLocalAccountUpdates()
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

    private func cleanUpUnknownIdentifiers() {
        let operation = StorageServiceOperation(mode: .cleanUpUnknownIdentifiers)
        StorageServiceOperation.operationQueue.addOperation(operation)
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

    private var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    private var groupV2Updates: GroupV2UpdatesSwift {
        return SSKEnvironment.shared.groupV2Updates as! GroupV2UpdatesSwift
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
        case cleanUpUnknownIdentifiers
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
        case .cleanUpUnknownIdentifiers:
            cleanUpUnknownIdentifiers()
        }
    }

    // MARK: - Mark Pending Changes: Accounts

    fileprivate static func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                let updatedAccountIds = updatedAddresses.map { address in
                    OWSAccountIdFinder().ensureAccountId(forAddress: address, transaction: transaction)
                }

                recordPendingUpdates(updatedAccountIds: updatedAccountIds, transaction: transaction)
            }
        }
    }

    fileprivate static func recordPendingUpdates(updatedAccountIds: [AccountId]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingUpdates(updatedAccountIds: updatedAccountIds, transaction: transaction)
            }
        }
    }

    private static func recordPendingUpdates(updatedAccountIds: [AccountId], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var state = State.current(transaction: transaction)

        let localAccountId = TSAccountManager.sharedInstance().localAccountId(transaction: transaction)

        for accountId in updatedAccountIds {
            if accountId == localAccountId {
                state.localAccountChangeState = .updated
                continue
            }

            state.accountIdChangeMap[accountId] = .updated
        }

        state.save(transaction: transaction)
    }

    fileprivate static func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                let deletedAccountIds = deletedAddresses.map { address in
                    OWSAccountIdFinder().ensureAccountId(forAddress: address, transaction: transaction)
                }

                recordPendingDeletions(deletedAccountIds: deletedAccountIds, transaction: transaction)
            }
        }
    }

    fileprivate static func recordPendingDeletions(deletedAccountIds: [AccountId]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingDeletions(deletedAccountIds: deletedAccountIds, transaction: transaction)
            }
        }
    }

    private static func recordPendingDeletions(deletedAccountIds: [AccountId], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var state = State.current(transaction: transaction)

        let localAccountId = TSAccountManager.sharedInstance().localAccountId(transaction: transaction)

        for accountId in deletedAccountIds {
            if accountId == localAccountId {
                owsFailDebug("the local account should never be flagged for deletion")
                continue
            }

            state.accountIdChangeMap[accountId] = .deleted
        }

        state.save(transaction: transaction)
    }

    fileprivate static func recordPendingLocalAccountUpdates() -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                var state = State.current(transaction: transaction)
                state.localAccountChangeState = .updated
                state.save(transaction: transaction)
            }
        }
    }

    // MARK: - Mark Pending Changes: v1 Groups

    fileprivate static func recordPendingUpdates(updatedGroupV1Ids: [Data]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingUpdates(updatedGroupV1Ids: updatedGroupV1Ids, transaction: transaction)
            }
        }
    }

    private static func recordPendingUpdates(updatedGroupV1Ids: [Data], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var state = State.current(transaction: transaction)

        for groupId in updatedGroupV1Ids {
            state.groupV1ChangeMap[groupId] = .updated
        }

        state.save(transaction: transaction)
    }

    fileprivate static func recordPendingDeletions(deletedGroupV1Ids: [Data]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingDeletions(deletedGroupV1Ids: deletedGroupV1Ids, transaction: transaction)
            }
        }
    }

    private static func recordPendingDeletions(deletedGroupV1Ids: [Data], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var state = State.current(transaction: transaction)

        for groupId in deletedGroupV1Ids {
            state.groupV1ChangeMap[groupId] = .deleted
        }

        state.save(transaction: transaction)
    }

    // MARK: - Mark Pending Changes: v2 Groups

    fileprivate static func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingUpdates(updatedGroupV2MasterKeys: updatedGroupV2MasterKeys, transaction: transaction)
            }
        }
    }

    private static func recordPendingUpdates(updatedGroupV2MasterKeys: [Data], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var state = State.current(transaction: transaction)

        for masterKey in updatedGroupV2MasterKeys {
            state.groupV2ChangeMap[masterKey] = .updated
        }

        state.save(transaction: transaction)
    }

    fileprivate static func recordPendingDeletions(deletedGroupV2MasterKeys: [Data]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingDeletions(deletedGroupV2MasterKeys: deletedGroupV2MasterKeys, transaction: transaction)
            }
        }
    }

    private static func recordPendingDeletions(deletedGroupV2MasterKeys: [Data], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var state = State.current(transaction: transaction)

        for masterKey in deletedGroupV2MasterKeys {
            state.groupV2ChangeMap[masterKey] = .deleted
        }

        state.save(transaction: transaction)
    }

    // MARK: - Backup

    private func backupPendingChanges() {
        var updatedItems: [StorageService.StorageItem] = []
        var deletedIdentifiers: [StorageService.StorageIdentifier] = []

        var state: State = databaseStorage.read { transaction in
            var state = State.current(transaction: transaction)

            // Build an up-to-date storage item for every pending account update
            updatedItems =
                state.accountIdChangeMap.lazy.filter { $0.value == .updated }.compactMap { accountId, _ in
                    do {
                        // If there is an existing identifier for this contact,
                        // mark it for deletion. We generate a fresh identifer
                        // every time a contact record changes so other devices
                        // know which records have changes to fetch.
                        if let storageIdentifier = state.accountIdToIdentifierMap[accountId] {
                            deletedIdentifiers.append(storageIdentifier)
                        }

                        // Generate a fresh identifier
                        let storageIdentifier = StorageService.StorageIdentifier.generate(type: .contact)
                        state.accountIdToIdentifierMap[accountId] = storageIdentifier

                        let contactRecord = try StorageServiceProtoContactRecord.build(for: accountId, transaction: transaction)
                        let storageItem = try StorageService.StorageItem(identifier: storageIdentifier, contact: contactRecord)

                        // Clear pending changes
                        state.accountIdChangeMap[accountId] = nil

                        return storageItem
                    } catch {
                        // If the accountId we're trying to backup is no longer associated with
                        // any known address, we no longer need to care about it. It's possible
                        // that account was unregistered / the SignalRecipient no longer exists.
                        if case StorageService.StorageError.accountMissing = error {
                            Logger.info("Clearing data for missing accountId \(accountId).")

                            state.accountIdToIdentifierMap[accountId] = nil
                            state.accountIdChangeMap[accountId] = nil
                        } else {
                            // If for some reason we failed, we'll just skip it and try this account again next backup.
                            owsFailDebug("Unexpectedly failed to process changes for account \(error)")
                        }

                        return nil
                    }
            }

            // Build an up-to-date storage item for every pending v1 group update
            updatedItems +=
                state.groupV1ChangeMap.lazy.filter { $0.value == .updated }.compactMap { groupId, _ in
                    do {
                        // If there is an existing identifier for this group,
                        // mark it for deletion. We generate a fresh identifer
                        // every time a contact record changes so other devices
                        // know which records have changes to fetch.
                        if let storageIdentifier = state.groupV1IdToIdentifierMap[groupId] {
                            deletedIdentifiers.append(storageIdentifier)
                        }

                        // Generate a fresh identifier
                        let storageIdentifier = StorageService.StorageIdentifier.generate(type: .groupv1)
                        state.groupV1IdToIdentifierMap[groupId] = storageIdentifier

                        let groupV1Record = try StorageServiceProtoGroupV1Record.build(for: groupId, transaction: transaction)
                        let storageItem = try StorageService.StorageItem(identifier: storageIdentifier, groupV1: groupV1Record)

                        // Clear pending changes
                        state.groupV1ChangeMap[groupId] = nil

                        return storageItem
                    } catch {
                        owsFailDebug("Unexpectedly failed to process changes for account \(error)")
                        // If for some reason we failed, we'll just skip it and try this account again next backup.
                        return nil
                    }
            }

            // Build an up-to-date storage item for every pending v2 group update
            updatedItems +=
                state.groupV2ChangeMap.lazy.filter { $0.value == .updated }.compactMap { groupMasterKey, _ in
                    do {
                        // If there is an existing identifier for this group,
                        // mark it for deletion. We generate a fresh identifer
                        // every time a contact record changes so other devices
                        // know which records have changes to fetch.
                        if let storageIdentifier = state.groupV2MasterKeyToIdentifierMap[groupMasterKey] {
                            deletedIdentifiers.append(storageIdentifier)
                        }

                        // Generate a fresh identifier
                        let storageIdentifier = StorageService.StorageIdentifier.generate(type: .groupv2)
                        state.groupV2MasterKeyToIdentifierMap[groupMasterKey] = storageIdentifier

                        let groupV2Record = try StorageServiceProtoGroupV2Record.build(for: groupMasterKey, transaction: transaction)
                        let storageItem = try StorageService.StorageItem(identifier: storageIdentifier, groupV2: groupV2Record)

                        // Clear pending changes
                        state.groupV2ChangeMap[groupMasterKey] = nil

                        return storageItem
                    } catch {
                        owsFailDebug("Unexpectedly failed to process changes for account \(error)")
                        // If for some reason we failed, we'll just skip it and try this account again next backup.
                        return nil
                    }
            }

            if state.localAccountChangeState == .updated {
                let accountItem: StorageService.StorageItem? = {
                    do {
                        // If there is an existing identifier, mark it for deletion.
                        // We generate a fresh identifer every time a contact record
                        // changes so other devices know which records have changes to fetch.
                        if let storageIdentifier = state.localAccountIdentifier {
                            deletedIdentifiers.append(storageIdentifier)
                        }

                        // Generate a fresh identifier
                        let storageIdentifier = StorageService.StorageIdentifier.generate(type: .account)
                        state.localAccountIdentifier = storageIdentifier

                        let accountRecord = try StorageServiceProtoAccountRecord.build(transaction: transaction)
                        let accountItem = try StorageService.StorageItem(identifier: storageIdentifier, account: accountRecord)

                        // Clear pending changes
                        state.localAccountChangeState = .unchanged

                        return accountItem
                    } catch {
                        owsFailDebug("Unexpectedly failed to process changes for account \(error)")
                        // If for some reason we failed, we'll just skip it and try this account again next backup.
                        return nil
                    }
                }()

                if let accountItem = accountItem {
                    updatedItems.append(accountItem)
                }
            }

            return state
        }

        // Lookup the identifier for every pending account deletion
        deletedIdentifiers +=
            state.accountIdChangeMap.lazy.filter { $0.value == .deleted }.compactMap { accountId, _ in
                // Clear the pending change
                state.accountIdChangeMap[accountId] = nil

                guard let identifier = state.accountIdToIdentifierMap[accountId] else {
                    // This contact doesn't exist in our records, it may have been
                    // added and then deleted before a backup occured. We can safely skip it.
                    return nil
                }

                // Remove this contact from the mapping
                state.accountIdToIdentifierMap[accountId] = nil

                return identifier
        }

        // Lookup the identifier for every pending group v1 deletion
        deletedIdentifiers +=
            state.groupV1ChangeMap.lazy.filter { $0.value == .deleted }.compactMap { groupId, _ in
                // Clear the pending change
                state.groupV1ChangeMap[groupId] = nil

                guard let identifier = state.groupV1IdToIdentifierMap[groupId] else {
                    // This group doesn't exist in our records, it may have been
                    // added and then deleted before a backup occured. We can safely skip it.
                    return nil
                }

                // Remove this group from the mapping
                state.groupV1IdToIdentifierMap[groupId] = nil

                return identifier
        }

        // Lookup the identifier for every pending group v2 deletion
        deletedIdentifiers +=
            state.groupV2ChangeMap.lazy.filter { $0.value == .deleted }.compactMap { groupMasterKey, _ in
                // Clear the pending change
                state.groupV2ChangeMap[groupMasterKey] = nil

                guard let identifier = state.groupV2MasterKeyToIdentifierMap[groupMasterKey] else {
                    // This group doesn't exist in our records, it may have been
                    // added and then deleted before a backup occured. We can safely skip it.
                    return nil
                }

                // Remove this group from the mapping
                state.groupV2MasterKeyToIdentifierMap[groupMasterKey] = nil

                return identifier
        }

        // If we have no pending changes, we have nothing left to do
        guard !deletedIdentifiers.isEmpty || !updatedItems.isEmpty else {
            return reportSuccess()
        }

        // Bump the manifest version
        state.manifestVersion += 1

        let manifest: StorageServiceProtoManifestRecord
        do {
            manifest = try buildManifestRecord(manifestVersion: state.manifestVersion,
                                               identifiers: state.allIdentifiers)
        } catch {
            return reportError(OWSAssertionError("failed to build proto with error: \(error)"))
        }

        Logger.info("Backing up pending changes with manifest version: \(state.manifestVersion). \(updatedItems.count) new items. \(deletedIdentifiers.count) deleted items. Total keys: \(state.allIdentifiers.count)")

        StorageService.updateManifest(
            manifest,
            newItems: updatedItems,
            deletedIdentifiers: deletedIdentifiers
        ).done(on: .global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                Logger.info("Successfully updated to manifest version: \(state.manifestVersion)")

                // Successfuly updated, store our changes.
                self.databaseStorage.write { transaction in
                    state.save(clearConsecutiveConflicts: true, transaction: transaction)
                }

                // Notify our other devices that the storage manifest has changed.
                OWSSyncManager.shared().sendFetchLatestStorageManifestSyncMessage()

                return self.reportSuccess()
            }

            // Throw away all our work, resolve conflicts, and try again.
            self.mergeLocalManifest(withRemoteManifest: conflictingManifest, backupAfterSuccess: true)
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    private func buildManifestRecord(manifestVersion: UInt64,
                                     identifiers identifiersParam: [StorageService.StorageIdentifier]) throws -> StorageServiceProtoManifestRecord {
        let identifiers = StorageService.StorageIdentifier.deduplicate(identifiersParam)
        let manifestBuilder = StorageServiceProtoManifestRecord.builder(version: manifestVersion)
        manifestBuilder.setKeys(try identifiers.map { try $0.buildRecord() })
        return try manifestBuilder.build()
    }

    // MARK: - Restore

    private func restoreOrCreateManifestIfNecessary() {
        let state: State = databaseStorage.read { State.current(transaction: $0) }

        StorageService.fetchLatestManifest(greaterThanVersion: state.manifestVersion).done(on: .global()) { response in
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
        }
    }

    private func createNewManifest(version: UInt64) {
        var allItems: [StorageService.StorageItem] = []
        var state = State()

        state.manifestVersion = version

        databaseStorage.read { transaction in
            SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                if recipient.address.isLocalAddress {
                    let identifier = StorageService.StorageIdentifier.generate(type: .account)
                    state.localAccountIdentifier = identifier

                    do {
                        let accountRecord = try StorageServiceProtoAccountRecord.build(transaction: transaction)
                        allItems.append(
                            try .init(identifier: identifier, account: accountRecord)
                        )
                    } catch {
                        // We'll just skip it, something may be wrong with our local data.
                        // We'll try and backup this account again when something changes.
                        owsFailDebug("failed to build account record with error: \(error)")
                    }

                } else if recipient.devices.count > 0 {
                    let identifier = StorageService.StorageIdentifier.generate(type: .contact)
                    state.accountIdToIdentifierMap[recipient.accountId] = identifier

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

                switch groupThread.groupModel.groupsVersion {
                case .V1:
                    let groupId = groupThread.groupModel.groupId
                    let identifier = StorageService.StorageIdentifier.generate(type: .groupv1)
                    state.groupV1IdToIdentifierMap[groupId] = identifier

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
                case .V2:
                    guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                        owsFailDebug("Invalid group model.")
                        return
                    }

                    do {
                        let groupMasterKey = try GroupsV2Protos.masterKeyData(forGroupModel: groupModel)
                        let identifier = StorageService.StorageIdentifier.generate(type: .groupv2)
                        state.groupV2MasterKeyToIdentifierMap[groupMasterKey] = identifier

                        let groupV2Record = try StorageServiceProtoGroupV2Record.build(for: groupMasterKey, transaction: transaction)
                        allItems.append(
                            try .init(identifier: identifier, groupV2: groupV2Record)
                        )
                    } catch {
                        // We'll just skip it, something may be wrong with our local data.
                        // We'll try and backup this group again when something changes.
                        owsFailDebug("failed to build group record with error: \(error)")
                    }
                }
            }
        }

        let manifest: StorageServiceProtoManifestRecord
        do {
            let identifiers = allItems.map { $0.identifier }
            manifest = try buildManifestRecord(manifestVersion: state.manifestVersion,
                                               identifiers: identifiers)
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
                    state.save(clearConsecutiveConflicts: true, transaction: transaction)
                }

                return self.reportSuccess()
            }

            // We got a conflicting manifest that we were able to decrypt, so we may not need
            // to recreate our manifest after all. Throw away all our work, resolve conflicts,
            // and try again.
            self.mergeLocalManifest(withRemoteManifest: conflictingManifest, backupAfterSuccess: true)
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    // MARK: - Conflict Resolution

    private func mergeLocalManifest(withRemoteManifest manifest: StorageServiceProtoManifestRecord, backupAfterSuccess: Bool) {
        var state: State = databaseStorage.write { transaction in
            var state = State.current(transaction: transaction)

            // Increment our conflict count.
            state.consecutiveConflicts += 1
            state.save(transaction: transaction)

            return state
        }

        // If we've tried many times in a row to resolve conflicts, something weird is happening
        // (potentially a bug on the service or a race with another app). Give up and wait until
        // the next backup runs.
        guard state.consecutiveConflicts <= StorageServiceOperation.maxConsecutiveConflicts else {
            owsFailDebug("unexpectedly have had numerous repeated conflicts")

            // Clear out the consecutive conflicts count so we can try again later.
            databaseStorage.write { transaction in
                state.save(clearConsecutiveConflicts: true, transaction: transaction)
            }

            return reportError(OWSAssertionError("exceeded max consectuive conflicts, creating a new manifest"))
        }

        // Calculate new or updated items by looking up the ids
        // of any items we don't know about locally. Since a new
        // id is always generated after a change, this should always
        // reflect the only items we need to fetch from the service.
        let allManifestItems: Set<StorageService.StorageIdentifier> = Set(manifest.keys.map { .init(data: $0.data, type: $0.type) })

        var newOrUpdatedItems = Array(allManifestItems.subtracting(state.allIdentifiers))

        let localKeysCount = state.allIdentifiers.count

        Logger.info("Merging with newer remote manifest version: \(manifest.version). \(newOrUpdatedItems.count) new or updated items. Remote key count: \(allManifestItems.count). Local key count: \(localKeysCount).")

        firstly { () -> Promise<Void> in
            // First, fetch the local account record if it has been updated. We give this record
            // priority over all other records as it contains things like the user's configuration
            // that we want to update ASAP, especially when restoring after linking.

            guard state.localAccountIdentifier == nil || !allManifestItems.contains(state.localAccountIdentifier!) else {
                return Promise.value(())
            }

            let localAccountIdentifiers = newOrUpdatedItems.filter { $0.type == .account }
            assert(localAccountIdentifiers.count == 1)

            guard let newLocalAccountIdentifier = localAccountIdentifiers.first else {
                owsFailDebug("remote manifest is missing local account, mark it for update")
                state.localAccountChangeState = .updated
                return Promise.value(())
            }

            Logger.info("Merging account record update from manifest version: \(manifest.version).")

            return StorageService.fetchItem(for: newLocalAccountIdentifier).done(on: .global()) { item in
                guard let item = item else {
                    // This can happen in normal use if between fetching the manifest and starting the item
                    // fetch a linked device has updated the manifest.
                    Logger.verbose("remote manifest contained an identifier for the local account that doesn't exist, mark it for update")
                    state.localAccountChangeState = .updated
                    return
                }

                guard let accountRecord = item.accountRecord else {
                    throw OWSAssertionError("unexpected item type for account identifier")
                }

                self.databaseStorage.write { transaction in
                    switch accountRecord.mergeWithLocalAccount(transaction: transaction) {
                    case .needsUpdate:
                        state.localAccountChangeState = .updated
                    case .resolved:
                        state.localAccountChangeState = .unchanged
                    }

                    state.localAccountIdentifier = item.identifier

                    state.save(transaction: transaction)
                }

                // Remove any account record identifiers from the new or updated basket. We've processed them.
                newOrUpdatedItems.removeAll { localAccountIdentifiers.contains($0) }
            }
        }.then(on: .global()) { () -> Promise<[StorageService.StorageItem]> in
            // Then, fetch the remaining items in the manifest and resolve any conflicts as appropriate.

            // Update the manifest version to reflect the remote version
            state.manifestVersion = manifest.version

            // Cleanup our unknown identifiers type map to only reflect
            // identifiers that still exist in the manifest.
            state.unknownIdentifiersTypeMap = state.unknownIdentifiersTypeMap.mapValues { Array(allManifestItems.intersection($0)) }

            return StorageService.fetchItems(for: newOrUpdatedItems)
        }.done(on: .global()) { items in
            self.databaseStorage.write { transaction in
                for item in items {
                    if let contactRecord = item.contactRecord {
                        guard contactRecord.serviceAddress?.isLocalAddress == false else {
                            owsFailDebug("Remote service contained contact record for local user. Only account record should exist for the local user.")
                            continue
                        }

                        switch contactRecord.mergeWithLocalContact(transaction: transaction) {
                        case .invalid:
                            // This contact record was invalid, ignore it.
                            // we'll clear it out in the next backup.
                            break

                        case .needsUpdate(let accountId):
                            // our local version was newer, flag this account as needing a sync
                            state.accountIdChangeMap[accountId] = .updated

                            // update the mapping
                            state.accountIdToIdentifierMap[accountId] = item.identifier

                        case .resolved(let accountId):
                            // We're all resolved, so if we had a pending change for this contact clear it out.
                            state.accountIdChangeMap[accountId] = nil

                            // update the mapping
                            state.accountIdToIdentifierMap[accountId] = item.identifier
                        }
                    } else if let groupV1Record = item.groupV1Record {
                        switch groupV1Record.mergeWithLocalGroup(transaction: transaction) {
                        case .invalid:
                            // This record was invalid, ignore it.
                            // we'll clear it out in the next backup.
                            break

                        case .needsUpdate(let groupId):
                            // our local version was newer, flag this account as needing a sync
                            state.groupV1ChangeMap[groupId] = .updated

                            // update the mapping
                            state.groupV1IdToIdentifierMap[groupId] = item.identifier

                        case .resolved(let groupId):
                            // We're all resolved, so if we had a pending change for this group clear it out.
                            state.groupV1ChangeMap[groupId] = nil

                            // update the mapping
                            state.groupV1IdToIdentifierMap[groupId] = item.identifier
                        }
                    } else if let groupV2Record = item.groupV2Record {
                        // If groups v2 isn't enabled, treat this record as unknown.
                        // We'll parse it when groups v2 is enabled.
                        guard FeatureFlags.groupsV2 else {
                            var unknownIdentifiersOfType = state.unknownIdentifiersTypeMap[item.identifier.type] ?? []
                            unknownIdentifiersOfType.append(item.identifier)
                            state.unknownIdentifiersTypeMap[item.identifier.type] = unknownIdentifiersOfType
                            continue
                        }

                        switch groupV2Record.mergeWithLocalGroup(transaction: transaction) {
                        case .invalid:
                            // This record was invalid, ignore it.
                            // we'll clear it out in the next backup.
                            break

                        case .needsUpdate(let groupMasterKey):
                            // our local version was newer, flag this account as needing a sync
                            state.groupV2ChangeMap[groupMasterKey] = .updated

                            // update the mapping
                            state.groupV2MasterKeyToIdentifierMap[groupMasterKey] = item.identifier

                            self.groupsV2.restoreGroupFromStorageServiceIfNecessary(masterKeyData: groupMasterKey,
                                                                                    transaction: transaction)

                        case .needsRefreshFromService(let groupMasterKey):
                            // We're all resolved, so if we had a pending change for this group clear it out.
                            state.groupV2ChangeMap[groupMasterKey] = nil

                            // update the mapping
                            state.groupV2MasterKeyToIdentifierMap[groupMasterKey] = item.identifier

                            self.groupsV2.restoreGroupFromStorageServiceIfNecessary(masterKeyData: groupMasterKey,
                                                                                    transaction: transaction)
                        case .resolved(let groupMasterKey):
                            // We're all resolved, so if we had a pending change for this group clear it out.
                            state.groupV2ChangeMap[groupMasterKey] = nil

                            // update the mapping
                            state.groupV2MasterKeyToIdentifierMap[groupMasterKey] = item.identifier
                        }
                    } else if case .account = item.identifier.type {
                        owsFailDebug("unexpectedly found account record in remaining items")
                    } else {
                        // This is not a record type we know about yet, so record this identifier in
                        // our unknown mapping. This allows us to skip fetching it in the future and
                        // not accidentally blow it away when we push an update.
                        var unknownIdentifiersOfType = state.unknownIdentifiersTypeMap[item.identifier.type] ?? []
                        unknownIdentifiersOfType.append(item.identifier)
                        state.unknownIdentifiersTypeMap[item.identifier.type] = unknownIdentifiersOfType
                    }

                }

                // Mark any orphaned records as pending update so we re-add them to the manifest.

                var orphanedGroupV1Count = 0
                Set(state.groupV1IdToIdentifierMap.backwardKeys).subtracting(allManifestItems).forEach { identifier in
                    if let groupId = state.groupV1IdToIdentifierMap[identifier] { state.groupV1ChangeMap[groupId] = .updated }
                    orphanedGroupV1Count += 1
                }

                var orphanedGroupV2Count = 0
                Set(state.groupV2MasterKeyToIdentifierMap.backwardKeys).subtracting(allManifestItems).forEach { identifier in
                    if let groupMasterKey = state.groupV2MasterKeyToIdentifierMap[identifier] { state.groupV2ChangeMap[groupMasterKey] = .updated }
                    orphanedGroupV2Count += 1
                }

                var orphanedAccountCount = 0
                Set(state.accountIdToIdentifierMap.backwardKeys).subtracting(allManifestItems).forEach { identifier in
                    if let accountId = state.accountIdToIdentifierMap[identifier] { state.accountIdChangeMap[accountId] = .updated }
                    orphanedAccountCount += 1
                }

                let pendingChangesCount = state.accountIdChangeMap.count + state.groupV1ChangeMap.count + state.groupV2ChangeMap.count

                Logger.info("Successfully merged with remote manifest version: \(manifest.version). \(pendingChangesCount) pending updates remaining including \(orphanedAccountCount) orphaned accounts and \(orphanedGroupV1Count) orphaned v1 groups and \(orphanedGroupV2Count) orphaned v2 groups.")

                state.save(clearConsecutiveConflicts: true, transaction: transaction)

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
        }
    }

    // MARK: - Clean Up Unknown Identifiers

    private func cleanUpUnknownIdentifiers() {
        databaseStorage.write { transaction in
            // We may have learned of new record types; if so we should
            // cull them from the unknownIdentifiersTypeMap on launch.
            var knownTypes: [StorageServiceProtoManifestRecordKeyType] = [
                .contact,
                .groupv1,
                .account
            ]

            if FeatureFlags.groupsV2 { knownTypes.append(.groupv2) }

            var state = State.current(transaction: transaction)

            let oldUnknownIdentifiersTypeMap = state.unknownIdentifiersTypeMap
            var newUnknownIdentifiersTypeMap = oldUnknownIdentifiersTypeMap
            knownTypes.forEach { newUnknownIdentifiersTypeMap[$0] = nil }
            guard oldUnknownIdentifiersTypeMap.count != newUnknownIdentifiersTypeMap.count else {
                // No change to record.
                return
            }

            state.unknownIdentifiersTypeMap = newUnknownIdentifiersTypeMap

            state.save(transaction: transaction)
        }

        return self.reportSuccess()
    }

    // MARK: - State

    private static var maxConsecutiveConflicts = 3

    private struct State: Codable {
        var manifestVersion: UInt64 = 0

        var consecutiveConflicts: Int = 0

        var localAccountIdentifier: StorageService.StorageIdentifier?
        var accountIdToIdentifierMap: BidirectionalDictionary<AccountId, StorageService.StorageIdentifier> = [:]
        var groupV1IdToIdentifierMap: BidirectionalDictionary<Data, StorageService.StorageIdentifier> = [:]
        var groupV2MasterKeyToIdentifierMap: BidirectionalDictionary<Data, StorageService.StorageIdentifier> = [:]

        var unknownIdentifiersTypeMap: [StorageServiceProtoManifestRecordKeyType: [StorageService.StorageIdentifier]] = [:]
        var unknownIdentifiers: [StorageService.StorageIdentifier] { unknownIdentifiersTypeMap.values.flatMap { $0 } }

        enum ChangeState: Int, Codable {
            case unchanged = 0
            case updated = 1
            case deleted = 2
        }

        var localAccountChangeState: ChangeState = .unchanged
        var accountIdChangeMap: [AccountId: ChangeState] = [:]
        var groupV1ChangeMap: [Data: ChangeState] = [:]
        var groupV2ChangeMap: [Data: ChangeState] = [:]

        var allIdentifiers: [StorageService.StorageIdentifier] {
            var allIdentifiers = [StorageService.StorageIdentifier]()
            if let localAccountIdentifier = localAccountIdentifier {
                allIdentifiers.append(localAccountIdentifier)
            }

            allIdentifiers += accountIdToIdentifierMap.backwardKeys
            allIdentifiers += groupV1IdToIdentifierMap.backwardKeys
            allIdentifiers += groupV2MasterKeyToIdentifierMap.backwardKeys

            // We must persist any unknown identifiers, as they are potentially associated with
            // valid records that this version of the app doesn't yet understand how to parse.
            // Otherwise, this will cause ping-ponging with newer apps when they try and backup
            // new types of records, and then we subsequently delete them.
            allIdentifiers += unknownIdentifiers

            return allIdentifiers
        }

        private static let stateKey = "state"

        static func current(transaction: SDSAnyReadTransaction) -> State {
            guard let stateData = keyValueStore.getData(stateKey, transaction: transaction) else { return State() }
            guard let current = try? JSONDecoder().decode(State.self, from: stateData) else {
                owsFailDebug("failed to decode state data")
                return State()
            }
            return current
        }

        mutating func save(clearConsecutiveConflicts: Bool = false, transaction: SDSAnyWriteTransaction) {
            if clearConsecutiveConflicts { consecutiveConflicts = 0 }
            guard let stateData = try? JSONEncoder().encode(self) else { return owsFailDebug("failed to encode state data") }
            keyValueStore.setData(stateData, key: State.stateKey, transaction: transaction)
        }
    }
}
