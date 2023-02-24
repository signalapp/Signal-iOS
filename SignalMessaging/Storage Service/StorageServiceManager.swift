//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SwiftProtobuf

@objc(OWSStorageServiceManager)
public class StorageServiceManager: NSObject, StorageServiceManagerProtocol {

    // TODO: We could convert this into a SSKEnvironment accessor so that we
    // can replace it in tests.
    @objc
    public static let shared = StorageServiceManager()

    override init() {
        super.init()

        SwiftSingletons.register(self)

        if CurrentAppContext().hasUI {
            AppReadiness.runNowOrWhenAppWillBecomeReady {
                self.cleanUpUnknownData()
            }

            AppReadiness.runNowOrWhenAppDidBecomeReadySync {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.willResignActive),
                    name: .OWSApplicationWillResignActive,
                    object: nil
                )
            }

            AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
                guard self.tsAccountManager.isRegisteredAndReady else { return }

                // Schedule a restore. This will do nothing unless we've never
                // registered a manifest before.
                self.restoreOrCreateManifestIfNecessary()

                // If we have any pending changes since we last launch, back them up now.
                self.backupPendingChanges()
            }
        }
    }

    @objc
    private func willResignActive() {
        // If we have any pending changes, start a back up immediately
        // to try and make sure the service doesn't get stale. If for
        // some reason we aren't able to successfully complete this backup
        // while in the background we'll try again on the next app launch.
        backupPendingChanges()
    }

    // MARK: -

    @objc
    public func recordPendingDeletions(deletedAccountIds: [AccountId]) {
        if deletedAccountIds.isEmpty {
            return
        }

        Logger.info("Recording pending deletions for account IDs: \(deletedAccountIds)")

        let operation = StorageServiceOperation.recordPendingDeletions(deletedAccountIds: deletedAccountIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) {
        if deletedAddresses.isEmpty {
            return
        }

        Logger.info("Recording pending deletions for addresses: \(deletedAddresses)")

        let operation = StorageServiceOperation.recordPendingDeletions(deletedAddresses: deletedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedGroupV1Ids: [Data]) {
        if deletedGroupV1Ids.isEmpty {
            return
        }

        let operation = StorageServiceOperation.recordPendingDeletions(deletedGroupV1Ids: deletedGroupV1Ids)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedGroupV2MasterKeys: [Data]) {
        if deletedGroupV2MasterKeys.isEmpty {
            return
        }

        let operation = StorageServiceOperation.recordPendingDeletions(deletedGroupV2MasterKeys: deletedGroupV2MasterKeys)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingDeletions(deletedStoryDistributionListIds: [Data]) {
        if deletedStoryDistributionListIds.isEmpty {
            return
        }

        let operation = StorageServiceOperation.recordPendingDeletions(deletedStoryDistributionListIds: deletedStoryDistributionListIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedAccountIds: [AccountId]) {
        if updatedAccountIds.isEmpty {
            return
        }

        Logger.info("Recording pending update for account IDs: \(updatedAccountIds)")

        let operation = StorageServiceOperation.recordPendingUpdates(updatedAccountIds: updatedAccountIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {
        if updatedAddresses.isEmpty {
            return
        }

        Logger.info("Recording pending update for addresses: \(updatedAddresses)")

        let operation = StorageServiceOperation.recordPendingUpdates(updatedAddresses: updatedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedGroupV1Ids: [Data]) {
        if updatedGroupV1Ids.isEmpty {
            return
        }

        let operation = StorageServiceOperation.recordPendingUpdates(updatedGroupV1Ids: updatedGroupV1Ids)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {
        if updatedGroupV2MasterKeys.isEmpty {
            return
        }

        let operation = StorageServiceOperation.recordPendingUpdates(updatedGroupV2MasterKeys: updatedGroupV2MasterKeys)
        StorageServiceOperation.operationQueue.addOperation(operation)

        scheduleBackupIfNecessary()
    }

    @objc
    public func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {
        if updatedStoryDistributionListIds.isEmpty {
            return
        }

        let operation = StorageServiceOperation.recordPendingUpdates(updatedStoryDistributionListIds: updatedStoryDistributionListIds)
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
        Logger.info("Recording pending local account updates")

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
        Logger.info("Resetting local storage service data.")
        StorageServiceOperation.keyValueStore.removeAll(transaction: transaction)
    }

    private func cleanUpUnknownData() {
        let operation = StorageServiceOperation(mode: .cleanUpUnknownData)
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

    @objc
    func backupTimerFired(_ timer: Timer) {
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

    public static var keyValueStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "kOWSStorageServiceOperation_IdentifierMap")
    }

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
        case cleanUpUnknownData
    }
    private let mode: Mode

    let promise: Promise<Void>
    private let future: Future<Void>

    fileprivate init(mode: Mode) {
        self.mode = mode
        (self.promise, self.future) = Promise<Void>.pending()
        super.init()
        self.remainingRetries = 4
    }

    // MARK: - Run

    override func didSucceed() {
        super.didSucceed()
        future.resolve()
    }

    override func didFail(error: Error) {
        super.didFail(error: error)
        future.reject(error)
    }

    // Called every retry, this is where the bulk of the operation's work should go.
    override public func run() {
        Logger.info("\(mode)")

        // We don't have backup keys, do nothing. We'll try a
        // fresh restore once the keys are set.
        guard DependenciesBridge.shared.keyBackupService.isKeyAvailable(.storageService) else {
            return reportSuccess()
        }

        // Under the new reg flow, we will sync kbs keys before being fully ready with
        // ts account manager auth set up. skip if so.
        if FeatureFlags.useNewRegistrationFlow, !tsAccountManager.isRegisteredAndReady {
            return reportSuccess()
        }

        switch mode {
        case .backup:
            backupPendingChanges()
        case .restoreOrCreate:
            restoreOrCreateManifestIfNecessary()
        case .cleanUpUnknownData:
            cleanUpUnknownData()
        }
    }

    // MARK: - Mark Pending Changes: Accounts

    fileprivate static func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                let updatedAccountIds = updatedAddresses.map { address in
                    OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
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

        let localAccountId = TSAccountManager.shared.localAccountId(transaction: transaction)

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
                    OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
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

        let localAccountId = TSAccountManager.shared.localAccountId(transaction: transaction)

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

    // MARK: - Mark Pending Changes: Private Stories

    fileprivate static func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingUpdates(updatedStoryDistributionListIds: updatedStoryDistributionListIds, transaction: transaction)
            }
        }
    }

    private static func recordPendingUpdates(updatedStoryDistributionListIds: [Data], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var state = State.current(transaction: transaction)

        for identifier in updatedStoryDistributionListIds {
            state.storyDistributionListChangeMap[identifier] = .updated
        }

        state.save(transaction: transaction)
    }

    fileprivate static func recordPendingDeletions(deletedStoryDistributionListIds: [Data]) -> Operation {
        return BlockOperation {
            databaseStorage.write { transaction in
                recordPendingDeletions(deletedStoryDistributionListIds: deletedStoryDistributionListIds, transaction: transaction)
            }
        }
    }

    private static func recordPendingDeletions(deletedStoryDistributionListIds: [Data], transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        var state = State.current(transaction: transaction)

        for identifier in deletedStoryDistributionListIds {
            state.storyDistributionListChangeMap[identifier] = .deleted
        }

        state.save(transaction: transaction)
    }

    // MARK: - Backup

    private func backupPendingChanges() {
        var updatedItems: [StorageService.StorageItem] = []
        var deletedIdentifiers: [StorageService.StorageIdentifier] = []

        func updateRecord<StateUpdater: StorageServiceStateUpdater>(
            state: inout State,
            localId: StateUpdater.IdType,
            changeState: State.ChangeState,
            stateUpdater: StateUpdater,
            transaction: SDSAnyReadTransaction
        ) {
            let recordUpdater = stateUpdater.recordUpdater

            let newRecord: StateUpdater.RecordType?

            switch changeState {
            case .unchanged:
                return
            case .updated:
                // We need to preserve the unknown fields (if any) so we don't blow away
                // data written by newer versions of the app.
                let recordWithUnknownFields = stateUpdater.recordWithUnknownFields(for: localId, in: state)
                let unknownFields = recordWithUnknownFields.flatMap { recordUpdater.unknownFields(for: $0) }
                newRecord = recordUpdater.buildRecord(for: localId, unknownFields: unknownFields, transaction: transaction)
            case .deleted:
                newRecord = nil
            }

            // Note: We might not have a `newRecord` even if the status is `.updated`.
            // The local value may have been deleted before this operation started.

            // If there is an existing identifier for this record, mark it for
            // deletion. We generate a fresh identifier every time a record changes, so
            // we always start by deleting the old record.
            if let oldStorageIdentifier = stateUpdater.storageIdentifier(for: localId, in: state) {
                deletedIdentifiers.append(oldStorageIdentifier)
            }
            // Clear out all of the state for the old record. We'll re-add the state if
            // we have a new record to save.
            stateUpdater.setStorageIdentifier(nil, for: localId, in: &state)
            stateUpdater.setRecordWithUnknownFields(nil, for: localId, in: &state)

            // We've deleted the old record. If we don't have a `newRecord`, stop.
            guard let newRecord else {
                return
            }

            if recordUpdater.unknownFields(for: newRecord) != nil {
                stateUpdater.setRecordWithUnknownFields(newRecord, for: localId, in: &state)
            }

            let storageItem = recordUpdater.buildStorageItem(for: newRecord)
            stateUpdater.setStorageIdentifier(storageItem.identifier, for: localId, in: &state)
            updatedItems.append(storageItem)
        }

        func updateRecords<StateUpdater: StorageServiceStateUpdater>(
            state: inout State,
            stateUpdater: StateUpdater,
            transaction: SDSAnyReadTransaction
        ) {
            stateUpdater.resetAndEnumerateChangeStates(in: &state) { mutableState, localId, changeState in
                updateRecord(
                    state: &mutableState,
                    localId: localId,
                    changeState: changeState,
                    stateUpdater: stateUpdater,
                    transaction: transaction
                )
            }
        }

        var state: State = databaseStorage.read { transaction in
            var state = State.current(transaction: transaction)

            updateRecords(state: &state, stateUpdater: buildContactUpdater(), transaction: transaction)
            updateRecords(state: &state, stateUpdater: buildGroupV1Updater(), transaction: transaction)
            updateRecords(state: &state, stateUpdater: buildGroupV2Updater(), transaction: transaction)
            updateRecords(state: &state, stateUpdater: buildStoryDistributionListUpdater(), transaction: transaction)

            if let accountUpdater = buildAccountUpdater() {
                updateRecords(state: &state, stateUpdater: accountUpdater, transaction: transaction)
            }

            return state
        }

        // If we have no pending changes, we have nothing left to do
        guard !deletedIdentifiers.isEmpty || !updatedItems.isEmpty else {
            return reportSuccess()
        }

        // If we have invalid identifiers, we intentionally exclude them from the
        // prior check. We've already ignored them, so we can clean them up as part
        // of the next unrelated change.
        let invalidIdentifiers = state.invalidIdentifiers
        state.invalidIdentifiers = []

        // Bump the manifest version
        state.manifestVersion += 1

        let manifest: StorageServiceProtoManifestRecord
        do {
            manifest = try buildManifestRecord(manifestVersion: state.manifestVersion,
                                               identifiers: state.allIdentifiers)
        } catch {
            return reportError(OWSAssertionError("failed to build proto with error: \(error)"))
        }

        Logger.info("Backing up pending changes with manifest version: \(state.manifestVersion) (New: \(updatedItems.count), Deleted: \(deletedIdentifiers.count), Invalid: \(invalidIdentifiers.count), Total: \(state.allIdentifiers.count))")

        StorageService.updateManifest(
            manifest,
            newItems: updatedItems,
            deletedIdentifiers: deletedIdentifiers + invalidIdentifiers
        ).done(on: DispatchQueue.global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                Logger.info("Successfully updated to manifest version: \(state.manifestVersion)")

                // Successfully updated, store our changes.
                self.databaseStorage.write { transaction in
                    state.save(clearConsecutiveConflicts: true, transaction: transaction)
                }

                // Notify our other devices that the storage manifest has changed.
                OWSSyncManager.shared.sendFetchLatestStorageManifestSyncMessage()

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
        var manifestBuilder = StorageServiceProtoManifestRecord.builder(version: manifestVersion)
        manifestBuilder.setKeys(try identifiers.map { try $0.buildRecord() })
        manifestBuilder.setSourceDevice(tsAccountManager.storedDeviceId())
        return try manifestBuilder.build()
    }

    // MARK: - Restore

    private func restoreOrCreateManifestIfNecessary() {
        let state: State = databaseStorage.read { State.current(transaction: $0) }

        let greaterThanVersion: UInt64? = {
            // If we've been flagged to refetch the latest manifest,
            // don't specify our current manifest version otherwise
            // the server may return nothing because we've said we
            // already parsed it.
            if state.refetchLatestManifest { return nil }
            return state.manifestVersion
        }()

        StorageService.fetchLatestManifest(greaterThanVersion: greaterThanVersion).done(on: DispatchQueue.global()) { response in
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
                    if TSAccountManager.shared.isPrimaryDevice {
                        Logger.info("Manifest decryption failed, recreating manifest.")
                        return self.createNewManifest(version: previousManifestVersion + 1)
                    }

                    Logger.info("Manifest decryption failed, clearing storage service keys.")

                    // If this is a linked device, give up and request the latest storage
                    // service key from the primary device.
                    self.databaseStorage.write { transaction in
                        // Clear out the key, it's no longer valid. This will prevent us
                        // from trying to backup again until the sync response is received.
                        DependenciesBridge.shared.keyBackupService.storeSyncedKey(type: .storageService, data: nil, transaction: transaction.asV2Write)
                        OWSSyncManager.shared.sendKeysSyncRequestMessage(transaction: transaction)
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
            func createRecord<StateUpdater: StorageServiceStateUpdater>(
                localId: StateUpdater.IdType,
                stateUpdater: StateUpdater
            ) {
                let recordUpdater = stateUpdater.recordUpdater

                let newRecord = recordUpdater.buildRecord(for: localId, unknownFields: nil, transaction: transaction)
                guard let newRecord else {
                    return
                }
                let storageItem = recordUpdater.buildStorageItem(for: newRecord)
                stateUpdater.setStorageIdentifier(storageItem.identifier, for: localId, in: &state)
                allItems.append(storageItem)
            }

            let accountUpdater = buildAccountUpdater()
            let contactUpdater = buildContactUpdater()
            SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                if recipient.address.isLocalAddress {
                    guard let accountUpdater else { return }
                    createRecord(localId: (), stateUpdater: accountUpdater)
                } else {
                    createRecord(localId: recipient.accountId, stateUpdater: contactUpdater)
                }
            }

            let groupV1Updater = buildGroupV1Updater()
            let groupV2Updater = buildGroupV2Updater()
            let storyDistributionListUpdater = buildStoryDistributionListUpdater()
            TSThread.anyEnumerate(transaction: transaction) { thread, _ in
                if let groupThread = thread as? TSGroupThread {
                    switch groupThread.groupModel.groupsVersion {
                    case .V1:
                        createRecord(localId: groupThread.groupModel.groupId, stateUpdater: groupV1Updater)
                    case .V2:
                        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                            owsFailDebug("Invalid group model.")
                            return
                        }
                        let groupMasterKey: Data
                        do {
                            groupMasterKey = try GroupsV2Protos.masterKeyData(forGroupModel: groupModel)
                        } catch {
                            owsFailDebug("Invalid group model \(error).")
                            return
                        }
                        createRecord(localId: groupMasterKey, stateUpdater: groupV2Updater)
                    }
                } else if let storyThread = thread as? TSPrivateStoryThread {
                    guard let distributionListId = storyThread.distributionListIdentifier else {
                        owsFailDebug("Missing distribution list id for story thread \(thread.uniqueId)")
                        return
                    }
                    createRecord(localId: distributionListId, stateUpdater: storyDistributionListUpdater)
                }
            }

            // Deleted Private Stories
            for distributionListId in TSPrivateStoryThread.allDeletedIdentifiers(transaction: transaction) {
                createRecord(localId: distributionListId, stateUpdater: storyDistributionListUpdater)
            }
        }

        let manifest: StorageServiceProtoManifestRecord
        do {
            let identifiers = allItems.map { $0.identifier }
            manifest = try buildManifestRecord(manifestVersion: state.manifestVersion, identifiers: identifiers)
        } catch {
            return reportError(OWSAssertionError("failed to build proto with error: \(error)"))
        }

        Logger.info("Creating a new manifest with manifest version: \(version). Total keys: \(allItems.count)")

        // We want to do this only when absolutely necessary as it's an expensive
        // query on the server. When we set this flag, the server will query and
        // purge any orphaned records.
        let shouldDeletePreviousRecords = version > 1

        StorageService.updateManifest(
            manifest,
            newItems: allItems,
            deleteAllExistingRecords: shouldDeletePreviousRecords
        ).done(on: DispatchQueue.global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                // Successfully updated, store our changes.
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

            return reportError(OWSAssertionError("exceeded max consecutive conflicts, creating a new manifest"))
        }

        // Calculate new or updated items by looking up the ids
        // of any items we don't know about locally. Since a new
        // id is always generated after a change, this should always
        // reflect the only items we need to fetch from the service.
        let allManifestItems: Set<StorageService.StorageIdentifier> = Set(manifest.keys.lazy.map { .init(data: $0.data, type: $0.type) })

        var newOrUpdatedItems = Array(allManifestItems.subtracting(state.allIdentifiers))

        let localKeysCount = state.allIdentifiers.count

        Logger.info("Merging with newer remote manifest version: \(manifest.version). \(newOrUpdatedItems.count) new or updated items. Remote key count: \(allManifestItems.count). Local key count: \(localKeysCount).")

        firstly { () -> Promise<Void> in
            // First, fetch the local account record if it has been updated. We give this record
            // priority over all other records as it contains things like the user's configuration
            // that we want to update ASAP, especially when restoring after linking.

            if let storageIdentifier = state.localAccountIdentifier, allManifestItems.contains(storageIdentifier) {
                return .value(())
            }

            let localAccountIdentifiers = newOrUpdatedItems.filter { $0.type == .account }
            assert(localAccountIdentifiers.count <= 1)

            guard let newLocalAccountIdentifier = localAccountIdentifiers.first else {
                owsFailDebug("remote manifest is missing local account, mark it for update")
                state.localAccountChangeState = .updated
                return Promise.value(())
            }

            Logger.info("Merging account record update from manifest version: \(manifest.version).")

            return StorageService.fetchItem(for: newLocalAccountIdentifier).done(on: DispatchQueue.global()) { item in
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

                guard let accountUpdater = self.buildAccountUpdater() else {
                    throw OWSAssertionError("can't update account record")
                }

                self.databaseStorage.write { transaction in
                    self.mergeRecord(
                        accountRecord,
                        identifier: item.identifier,
                        state: &state,
                        stateUpdater: accountUpdater,
                        transaction: transaction
                    )
                    state.save(transaction: transaction)
                }

                // Remove any account record identifiers from the new or updated basket. We've processed them.
                newOrUpdatedItems.removeAll { localAccountIdentifiers.contains($0) }
            }
        }.then(on: DispatchQueue.global()) { () -> Promise<State> in
            // Cleanup our unknown identifiers type map to only reflect
            // identifiers that still exist in the manifest.
            state.unknownIdentifiersTypeMap = state.unknownIdentifiersTypeMap.mapValues { Array(allManifestItems.intersection($0)) }

            // Then, fetch the remaining items in the manifest and resolve any conflicts as appropriate.
            return self.fetchAndMergeItemsInBatches(identifiers: newOrUpdatedItems, manifest: manifest, state: state)
        }.done(on: DispatchQueue.global()) { updatedState in
            var mutableState = updatedState
            self.databaseStorage.write { transaction in
                // Update the manifest version to reflect the remote version we just restored to
                mutableState.manifestVersion = manifest.version

                // We just did a successful manifest fetch and restore, so we no longer need to refetch it
                mutableState.refetchLatestManifest = false

                // Save invalid identifiers to remove during the write operation.
                //
                // We don't remove them immediately because we've already ignored them, and
                // we want to avoid fighting against another device that may put them back
                // when we remove them. Instead, we simply keep track of them so that we
                // can delete them during our next mutation.
                //
                // We may have invalid identifiers for two reasons:
                //
                // (1) We got back an .invalid merge result, meaning we didn't process a
                // storage item. As a result, our local state won't reference it.
                //
                // (2) There are two storage items (with different storage identifiers)
                // whose contents refer to the same thing (eg, group, story). In this case,
                // the latter will replace the former, and the former will be orphaned.

                mutableState.invalidIdentifiers = allManifestItems.subtracting(mutableState.allIdentifiers)
                let invalidIdentifierCount = mutableState.invalidIdentifiers.count

                // Mark any orphaned records as pending update so we re-add them to the manifest.

                var orphanedGroupV1Count = 0
                for (groupId, identifier) in mutableState.groupV1IdToIdentifierMap where !allManifestItems.contains(identifier) {
                    mutableState.groupV1ChangeMap[groupId] = .updated
                    orphanedGroupV1Count += 1
                }

                var orphanedGroupV2Count = 0
                for (groupMasterKey, identifier) in mutableState.groupV2MasterKeyToIdentifierMap where !allManifestItems.contains(identifier) {
                    mutableState.groupV2ChangeMap[groupMasterKey] = .updated
                    orphanedGroupV2Count += 1
                }

                var orphanedStoryDistributionListCount = 0
                for (dlistIdentifier, storageIdentifier) in mutableState.storyDistributionListIdentifierToStorageIdentifierMap where !allManifestItems.contains(storageIdentifier) {
                    mutableState.storyDistributionListChangeMap[dlistIdentifier] = .updated
                    orphanedStoryDistributionListCount += 1
                }

                var orphanedAccountCount = 0
                let currentDate = Date()
                for (accountId, identifier) in mutableState.accountIdToIdentifierMap where !allManifestItems.contains(identifier) {
                    // Only consider registered recipients as orphaned. If another client
                    // removes an unregistered recipient, allow it.
                    guard
                        let storageServiceContact = StorageServiceContact.fetch(for: accountId, transaction: transaction),
                        storageServiceContact.shouldBeInStorageService(currentDate: currentDate),
                        storageServiceContact.registrationStatus(currentDate: currentDate) == .registered
                    else {
                        continue
                    }
                    mutableState.accountIdChangeMap[accountId] = .updated
                    orphanedAccountCount += 1
                }

                let pendingChangesCount = mutableState.accountIdChangeMap.count + mutableState.groupV1ChangeMap.count + mutableState.groupV2ChangeMap.count + mutableState.storyDistributionListChangeMap.count

                Logger.info("Successfully merged remote manifest \(manifest.version) (Pending Updates: \(pendingChangesCount); Invalid IDs: \(invalidIdentifierCount); Orphaned Accounts: \(orphanedAccountCount); Orphaned GV1: \(orphanedGroupV1Count); Orphaned GV2: \(orphanedGroupV2Count); Orphaned DLists: \(orphanedStoryDistributionListCount))")

                mutableState.save(clearConsecutiveConflicts: true, transaction: transaction)

                if backupAfterSuccess { StorageServiceManager.shared.backupPendingChanges() }
            }
            self.reportSuccess()
        }.catch { error in
            if let storageError = error as? StorageService.StorageError {

                // If we succeeded to fetch the records but were unable to decrypt any of them,
                // it likely means our keys changed.
                if case .itemDecryptionFailed = storageError {
                    // If this is the primary device, throw everything away and re-encrypt
                    // the social graph with the keys we have locally.
                    if TSAccountManager.shared.isPrimaryDevice {
                        Logger.info("Item decryption failed, recreating manifest.")
                        return self.createNewManifest(version: manifest.version + 1)
                    }

                    Logger.info("Item decryption failed, clearing storage service keys.")

                    // If this is a linked device, give up and request the latest storage
                    // service key from the primary device.
                    self.databaseStorage.write { transaction in
                        // Clear out the key, it's no longer valid. This will prevent us
                        // from trying to backup again until the sync response is received.
                        DependenciesBridge.shared.keyBackupService.storeSyncedKey(type: .storageService, data: nil, transaction: transaction.asV2Write)
                        OWSSyncManager.shared.sendKeysSyncRequestMessage(transaction: transaction)
                    }
                }

                return self.reportError(storageError)
            }

            self.reportError(withUndefinedRetry: error)
        }
    }

    private static var itemsBatchSize: Int { CurrentAppContext().isNSE ? 256 : 1024 }
    private func fetchAndMergeItemsInBatches(
        identifiers: [StorageService.StorageIdentifier],
        manifest: StorageServiceProtoManifestRecord,
        state: State
    ) -> Promise<State> {
        var remainingItems = identifiers.count
        var mutableState = state
        var promise = Promise.value(())
        for batch in identifiers.chunked(by: Self.itemsBatchSize) {
            promise = promise.then(on: DispatchQueue.global()) {
                StorageService.fetchItems(for: Array(batch))
            }.done(on: DispatchQueue.global()) { items in
                self.databaseStorage.write { transaction in
                    let contactUpdater = self.buildContactUpdater()
                    let groupV1Updater = self.buildGroupV1Updater()
                    let groupV2Updater = self.buildGroupV2Updater()
                    let storyDistributionListUpdater = self.buildStoryDistributionListUpdater()
                    for item in items {
                        func _mergeRecord<StateUpdater: StorageServiceStateUpdater>(
                            _ record: StateUpdater.RecordType,
                            stateUpdater: StateUpdater
                        ) {
                            self.mergeRecord(
                                record,
                                identifier: item.identifier,
                                state: &mutableState,
                                stateUpdater: stateUpdater,
                                transaction: transaction
                            )
                        }

                        if let contactRecord = item.contactRecord {
                            _mergeRecord(contactRecord, stateUpdater: contactUpdater)
                        } else if let groupV1Record = item.groupV1Record {
                            _mergeRecord(groupV1Record, stateUpdater: groupV1Updater)
                        } else if let groupV2Record = item.groupV2Record {
                            _mergeRecord(groupV2Record, stateUpdater: groupV2Updater)
                        } else if let storyDistributionListRecord = item.storyDistributionListRecord {
                            _mergeRecord(storyDistributionListRecord, stateUpdater: storyDistributionListUpdater)
                        } else if case .account = item.identifier.type {
                            owsFailDebug("unexpectedly found account record in remaining items")
                        } else {
                            // This is not a record type we know about yet, so record this identifier in
                            // our unknown mapping. This allows us to skip fetching it in the future and
                            // not accidentally blow it away when we push an update.
                            var unknownIdentifiersOfType = mutableState.unknownIdentifiersTypeMap[item.identifier.type] ?? []
                            unknownIdentifiersOfType.append(item.identifier)
                            mutableState.unknownIdentifiersTypeMap[item.identifier.type] = unknownIdentifiersOfType
                        }
                    }

                    remainingItems -= batch.count

                    Logger.info("Successfully merged \(batch.count) items from remote manifest version: \(manifest.version) with source device \(manifest.hasSourceDevice ? String(manifest.sourceDevice) : "(unspecified)"). \(remainingItems) items remaining to merge.")

                    // Saving here records the new storage identifiers with the *old* manifest version. This allows us to
                    // incrementally work through changes in a manifest, even if we fail part way through the update we'll
                    // continue trying to apply the changes we haven't received yet (since we still know we're on an older
                    // version overall).
                    mutableState.save(clearConsecutiveConflicts: true, transaction: transaction)
                }
            }
        }
        return promise.map { mutableState }
    }

    // MARK: - Clean Up

    private func cleanUpUnknownData() {
        databaseStorage.write { transaction in
            self.cleanUpUnknownIdentifiers(transaction: transaction)
            self.cleanUpRecordsWithUnknownFields(transaction: transaction)
            self.cleanUpOrphanedAccounts(transaction: transaction)
        }

        return self.reportSuccess()
    }

    private func cleanUpUnknownIdentifiers(transaction: SDSAnyWriteTransaction) {
        // We may have learned of new record types; if so we should
        // cull them from the unknownIdentifiersTypeMap on launch.
        let knownTypes: [StorageServiceProtoManifestRecordKeyType] = [
            .contact,
            .groupv1,
            .groupv2,
            .account,
            .storyDistributionList
        ]

        var state = State.current(transaction: transaction)

        let oldUnknownIdentifiersTypeMap = state.unknownIdentifiersTypeMap
        var newUnknownIdentifiersTypeMap = oldUnknownIdentifiersTypeMap
        knownTypes.forEach { newUnknownIdentifiersTypeMap[$0] = nil }
        guard oldUnknownIdentifiersTypeMap.count != newUnknownIdentifiersTypeMap.count else {
            // No change to record.
            return
        }

        state.unknownIdentifiersTypeMap = newUnknownIdentifiersTypeMap

        // If we cleaned up some unknown identifiers, we want to re-fetch
        // the latest manifest even if we've already fetched it, so we
        // can parse the unknown values.
        state.refetchLatestManifest = true

        state.save(transaction: transaction)
    }

    private func cleanUpRecordsWithUnknownFields(transaction: SDSAnyWriteTransaction) {
        var state = State.current(transaction: transaction)

        var shouldSave = false

        // For any cached records with unknown fields, optimistically try to merge
        // with our local data to see if we now understand those fields. Note: It's
        // possible and expected that we might understand some of the fields that
        // were previously unknown but not all of them. Even if we can't fully
        // merge any values, we might partially merge all the values.
        func mergeRecordsWithUnknownFields(stateUpdater: some StorageServiceStateUpdater) {
            let recordsWithUnknownFields = stateUpdater.recordsWithUnknownFields(in: state)
            if recordsWithUnknownFields.isEmpty {
                return
            }

            // If we have records with unknown fields, we'll try to merge them. In that
            // case, we should ensure we save the updated State object to disk.
            shouldSave = true

            let debugDescription = "\(type(of: stateUpdater.recordUpdater))"
            for (localId, recordWithUnknownFields) in recordsWithUnknownFields {
                guard let storageIdentifier = stateUpdater.storageIdentifier(for: localId, in: state) else {
                    owsFailDebug("Unknown fields: Missing identifier for \(debugDescription)")
                    stateUpdater.setRecordWithUnknownFields(nil, for: localId, in: &state)
                    continue
                }
                // If we call `mergeRecord` for any record, we should save an updated copy
                // of `state`. (We do this by setting `shouldSave` to true, above.) Even if
                // we can't fully merge all the unknown fields, we might be able to merge
                // *some* of the unknown fields.
                mergeRecord(
                    recordWithUnknownFields,
                    identifier: storageIdentifier,
                    state: &state,
                    stateUpdater: stateUpdater,
                    transaction: transaction
                )
            }
            let remainingCount = stateUpdater.recordsWithUnknownFields(in: state).count
            let resolvedCount = recordsWithUnknownFields.count - remainingCount
            Logger.info("Unknown fields: Resolved \(resolvedCount) records (\(remainingCount) remaining) for \(debugDescription)")
        }

        if let accountUpdater = buildAccountUpdater() {
            mergeRecordsWithUnknownFields(stateUpdater: accountUpdater)
        }
        mergeRecordsWithUnknownFields(stateUpdater: buildContactUpdater())
        mergeRecordsWithUnknownFields(stateUpdater: buildGroupV1Updater())
        mergeRecordsWithUnknownFields(stateUpdater: buildGroupV2Updater())
        mergeRecordsWithUnknownFields(stateUpdater: buildStoryDistributionListUpdater())

        if shouldSave {
            Logger.info("Resolved unknown fields using manifest version \(state.manifestVersion)")
            state.save(transaction: transaction)
        }
    }

    private func cleanUpOrphanedAccounts(transaction: SDSAnyWriteTransaction) {
        // We don't keep unregistered accounts in storage service after a certain
        // amount of time. We may also have records for accounts that no longer
        // exist, e.g. that SignalRecipient was merged with another recipient. We
        // try to proactively delete these records from storage service, but there
        // was a period of time we didn't, and we need to cleanup after ourselves.

        let currentDate = Date()

        func shouldRecipientBeInStorageService(accountId: AccountId) -> Bool {
            guard let storageServiceContact = StorageServiceContact.fetch(for: accountId, transaction: transaction) else {
                return false
            }
            return storageServiceContact.shouldBeInStorageService(currentDate: currentDate)
        }

        let orphanedAccountIds = State.current(transaction: transaction).accountIdToIdentifierMap.keys.filter {
            !shouldRecipientBeInStorageService(accountId: $0)
        }

        guard !orphanedAccountIds.isEmpty else { return }

        Logger.info("Marking \(orphanedAccountIds.count) orphaned account(s) for deletion.")

        StorageServiceOperation.recordPendingDeletions(
            deletedAccountIds: orphanedAccountIds,
            transaction: transaction
        )
    }

    // MARK: - Record Merge

    private func mergeRecord<StateUpdater: StorageServiceStateUpdater>(
        _ record: StateUpdater.RecordType,
        identifier: StorageService.StorageIdentifier,
        state: inout State,
        stateUpdater: StateUpdater,
        transaction: SDSAnyWriteTransaction
    ) {
        let mergeResult = stateUpdater.recordUpdater.mergeRecord(record, transaction: transaction)
        switch mergeResult {
        case .invalid:
            // This record doesn't have a valid identifier. We can't fix it, so we have
            // no choice but to delete it.
            break

        case .merged(needsUpdate: let needsUpdate, let localId):
            // Mark that our local state matches the state from storage service.
            stateUpdater.setStorageIdentifier(identifier, for: localId, in: &state)

            // If we have local changes that need to be synced, mark the state as
            // `.updated`. Otherwise, our local state and storage service state match,
            // so we can clear out any pending sync request.
            stateUpdater.setChangeState(needsUpdate ? .updated : nil, for: localId, in: &state)

            // If the record has unknown fields, we need to hold on to it. This allows
            // future versions of the app to interpret those fields.
            let hasUnknownFields = stateUpdater.recordUpdater.unknownFields(for: record) != nil
            stateUpdater.setRecordWithUnknownFields(hasUnknownFields ? record : nil, for: localId, in: &state)
        }
    }

    // MARK: - Record Updaters

    private func buildAccountUpdater() -> SingleElementStateUpdater<StorageServiceAccountRecordUpdater>? {
        guard
            let localAddress = TSAccountManager.localAddress,
            let localAci = localAddress.uuid
        else {
            owsFailDebug("Can't update local account without local address and ACI.")
            return nil
        }
        return SingleElementStateUpdater(
            recordUpdater: StorageServiceAccountRecordUpdater(
                localAddress: localAddress,
                localAci: localAci,
                paymentsHelper: paymentsHelperSwift,
                preferences: preferences,
                profileManager: profileManagerImpl,
                receiptManager: receiptManager,
                storageServiceManager: storageServiceManager,
                subscriptionManager: subscriptionManager,
                systemStoryManager: systemStoryManager,
                tsAccountManager: tsAccountManager,
                typingIndicators: typingIndicatorsImpl,
                udManager: udManager,
                usernameLookupManager: DependenciesBridge.shared.usernameLookupManager,
                usernameEducationManager: DependenciesBridge.shared.usernameEducationManager
            ),
            changeState: \.localAccountChangeState,
            storageIdentifier: \.localAccountIdentifier,
            recordWithUnknownFields: \.localAccountRecordWithUnknownFields
        )
    }

    private func buildContactUpdater() -> MultipleElementStateUpdater<StorageServiceContactRecordUpdater> {
        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceContactRecordUpdater(
                blockingManager: blockingManager,
                bulkProfileFetch: bulkProfileFetch,
                contactsManager: contactsManagerImpl,
                identityManager: identityManager,
                profileManager: profileManagerImpl,
                tsAccountManager: tsAccountManager,
                usernameLookupManager: DependenciesBridge.shared.usernameLookupManager
            ),
            changeState: \.accountIdChangeMap,
            storageIdentifier: \.accountIdToIdentifierMap,
            recordWithUnknownFields: \.accountIdToRecordWithUnknownFields
        )
    }

    private func buildGroupV1Updater() -> MultipleElementStateUpdater<StorageServiceGroupV1RecordUpdater> {
        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceGroupV1RecordUpdater(blockingManager: blockingManager, profileManager: profileManager),
            changeState: \.groupV1ChangeMap,
            storageIdentifier: \.groupV1IdToIdentifierMap,
            recordWithUnknownFields: \.groupV1IdToRecordWithUnknownFields
        )
    }

    private func buildGroupV2Updater() -> MultipleElementStateUpdater<StorageServiceGroupV2RecordUpdater> {
        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceGroupV2RecordUpdater(
                blockingManager: blockingManager,
                groupsV2: groupsV2Swift,
                profileManager: profileManager
            ),
            changeState: \.groupV2ChangeMap,
            storageIdentifier: \.groupV2MasterKeyToIdentifierMap,
            recordWithUnknownFields: \.groupV2MasterKeyToRecordWithUnknownFields
        )
    }

    private func buildStoryDistributionListUpdater() -> MultipleElementStateUpdater<StorageServiceStoryDistributionListRecordUpdater> {
        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceStoryDistributionListRecordUpdater(),
            changeState: \.storyDistributionListChangeMap,
            storageIdentifier: \.storyDistributionListIdentifierToStorageIdentifierMap,
            recordWithUnknownFields: \.storyDistributionListIdentifierToRecordWithUnknownFields
        )
    }

    // MARK: - State

    private static var maxConsecutiveConflicts = 3

    struct State: Codable {
        fileprivate var manifestVersion: UInt64 = 0
        private var _refetchLatestManifest: Bool?
        fileprivate var refetchLatestManifest: Bool {
            get { _refetchLatestManifest ?? false }
            set { _refetchLatestManifest = newValue }
        }

        fileprivate var consecutiveConflicts: Int = 0

        fileprivate var localAccountIdentifier: StorageService.StorageIdentifier?
        fileprivate var localAccountRecordWithUnknownFields: StorageServiceProtoAccountRecord?

        @BidirectionalLegacyDecoding
        fileprivate var accountIdToIdentifierMap: [AccountId: StorageService.StorageIdentifier] = [:]
        private var _accountIdToRecordWithUnknownFields: [AccountId: StorageServiceProtoContactRecord]?
        var accountIdToRecordWithUnknownFields: [AccountId: StorageServiceProtoContactRecord] {
            get { _accountIdToRecordWithUnknownFields ?? [:] }
            set { _accountIdToRecordWithUnknownFields = newValue }
        }

        @BidirectionalLegacyDecoding
        fileprivate var groupV1IdToIdentifierMap: [Data: StorageService.StorageIdentifier] = [:]
        private var _groupV1IdToRecordWithUnknownFields: [Data: StorageServiceProtoGroupV1Record]?
        var groupV1IdToRecordWithUnknownFields: [Data: StorageServiceProtoGroupV1Record] {
            get { _groupV1IdToRecordWithUnknownFields ?? [:] }
            set { _groupV1IdToRecordWithUnknownFields = newValue }
        }

        @BidirectionalLegacyDecoding
        fileprivate var groupV2MasterKeyToIdentifierMap: [Data: StorageService.StorageIdentifier] = [:]
        private var _groupV2MasterKeyToRecordWithUnknownFields: [Data: StorageServiceProtoGroupV2Record]?
        var groupV2MasterKeyToRecordWithUnknownFields: [Data: StorageServiceProtoGroupV2Record] {
            get { _groupV2MasterKeyToRecordWithUnknownFields ?? [:] }
            set { _groupV2MasterKeyToRecordWithUnknownFields = newValue }
        }

        private var _storyDistributionListIdentifierToStorageIdentifierMap: [Data: StorageService.StorageIdentifier]?
        fileprivate var storyDistributionListIdentifierToStorageIdentifierMap: [Data: StorageService.StorageIdentifier] {
            get { _storyDistributionListIdentifierToStorageIdentifierMap ?? [:] }
            set { _storyDistributionListIdentifierToStorageIdentifierMap = newValue }
        }
        private var _storyDistributionListIdentifierToRecordWithUnknownFields: [Data: StorageServiceProtoStoryDistributionListRecord]?
        fileprivate var storyDistributionListIdentifierToRecordWithUnknownFields: [Data: StorageServiceProtoStoryDistributionListRecord] {
            get { _storyDistributionListIdentifierToRecordWithUnknownFields ?? [:] }
            set { _storyDistributionListIdentifierToRecordWithUnknownFields = newValue }
        }

        fileprivate var unknownIdentifiersTypeMap: [StorageServiceProtoManifestRecordKeyType: [StorageService.StorageIdentifier]] = [:]
        fileprivate var unknownIdentifiers: [StorageService.StorageIdentifier] { unknownIdentifiersTypeMap.values.flatMap { $0 } }

        /// Invalid identifiers from the most recent merge that should be removed
        /// during the next mutation.
        fileprivate var invalidIdentifiers: Set<StorageService.StorageIdentifier> {
            get { _invalidIdentifiers ?? Set() }
            set { _invalidIdentifiers = newValue.isEmpty ? nil : newValue }
        }
        fileprivate var _invalidIdentifiers: Set<StorageService.StorageIdentifier>?

        enum ChangeState: Int, Codable {
            case unchanged = 0
            case updated = 1
            case deleted = 2
        }

        fileprivate var localAccountChangeState: ChangeState = .unchanged
        fileprivate var accountIdChangeMap: [AccountId: ChangeState] = [:]
        fileprivate var groupV1ChangeMap: [Data: ChangeState] = [:]
        fileprivate var groupV2ChangeMap: [Data: ChangeState] = [:]

        private var _storyDistributionListChangeMap: [Data: ChangeState]?
        fileprivate var storyDistributionListChangeMap: [Data: ChangeState] {
            get { _storyDistributionListChangeMap ?? [:] }
            set { _storyDistributionListChangeMap = newValue }
        }

        fileprivate var allIdentifiers: [StorageService.StorageIdentifier] {
            var allIdentifiers = [StorageService.StorageIdentifier]()
            if let localAccountIdentifier = localAccountIdentifier {
                allIdentifiers.append(localAccountIdentifier)
            }

            allIdentifiers += accountIdToIdentifierMap.values
            allIdentifiers += groupV1IdToIdentifierMap.values
            allIdentifiers += groupV2MasterKeyToIdentifierMap.values
            allIdentifiers += storyDistributionListIdentifierToStorageIdentifierMap.values

            // We must persist any unknown identifiers, as they are potentially associated with
            // valid records that this version of the app doesn't yet understand how to parse.
            // Otherwise, this will cause ping-ponging with newer apps when they try and backup
            // new types of records, and then we subsequently delete them.
            allIdentifiers += unknownIdentifiers

            return allIdentifiers
        }

        private static let stateKey = "state"

        fileprivate static func current(transaction: SDSAnyReadTransaction) -> State {
            guard let stateData = keyValueStore.getData(stateKey, transaction: transaction) else { return State() }
            guard let current = try? JSONDecoder().decode(State.self, from: stateData) else {
                owsFailDebug("failed to decode state data")
                return State()
            }
            return current
        }

        fileprivate mutating func save(clearConsecutiveConflicts: Bool = false, transaction: SDSAnyWriteTransaction) {
            if clearConsecutiveConflicts { consecutiveConflicts = 0 }
            guard let stateData = try? JSONEncoder().encode(self) else { return owsFailDebug("failed to encode state data") }
            keyValueStore.setData(stateData, key: State.stateKey, transaction: transaction)
        }

    }
}

// MARK: - State Updaters

protocol StorageServiceStateUpdater {
    associatedtype RecordUpdaterType: StorageServiceRecordUpdater

    typealias IdType = RecordUpdaterType.IdType
    typealias RecordType = RecordUpdaterType.RecordType
    typealias State = StorageServiceOperation.State

    var recordUpdater: RecordUpdaterType { get }

    func changeState(for localId: IdType, in state: State) -> State.ChangeState?
    func setChangeState(_ changeState: State.ChangeState?, for localId: IdType, in state: inout State)
    func resetAndEnumerateChangeStates(in state: inout State, block: (inout State, IdType, State.ChangeState) -> Void)

    func storageIdentifier(for localId: IdType, in state: State) -> StorageService.StorageIdentifier?
    func setStorageIdentifier(_ storageIdentifier: StorageService.StorageIdentifier?, for localId: IdType, in state: inout State)

    func recordWithUnknownFields(for localId: IdType, in state: State) -> RecordType?
    func setRecordWithUnknownFields(_ recordWithUnknownFields: RecordType?, for localId: IdType, in state: inout State)

    func recordsWithUnknownFields(in state: State) -> [(IdType, RecordType)]
}

private struct SingleElementStateUpdater<RecordUpdaterType: StorageServiceRecordUpdater>: StorageServiceStateUpdater where RecordUpdaterType.IdType == Void {
    typealias IdType = RecordUpdaterType.IdType
    typealias RecordType = RecordUpdaterType.RecordType
    typealias State = StorageServiceOperation.State

    let recordUpdater: RecordUpdaterType

    private let changeStateKeyPath: WritableKeyPath<State, State.ChangeState>
    private let storageIdentifierKeyPath: WritableKeyPath<State, StorageService.StorageIdentifier?>
    private let recordWithUnknownFieldsKeyPath: WritableKeyPath<State, RecordType?>

    init(
        recordUpdater: RecordUpdaterType,
        changeState: WritableKeyPath<State, State.ChangeState>,
        storageIdentifier: WritableKeyPath<State, StorageService.StorageIdentifier?>,
        recordWithUnknownFields: WritableKeyPath<State, RecordType?>
    ) {
        self.recordUpdater = recordUpdater
        self.changeStateKeyPath = changeState
        self.storageIdentifierKeyPath = storageIdentifier
        self.recordWithUnknownFieldsKeyPath = recordWithUnknownFields
    }

    func changeState(for localId: IdType, in state: State) -> State.ChangeState? {
        state[keyPath: changeStateKeyPath]
    }

    func setChangeState(_ changeState: State.ChangeState?, for localId: IdType, in state: inout State) {
        state[keyPath: changeStateKeyPath] = changeState ?? .unchanged
    }

    func resetAndEnumerateChangeStates(in state: inout State, block: (inout State, IdType, State.ChangeState) -> Void) {
        let oldState = state[keyPath: changeStateKeyPath]
        state[keyPath: changeStateKeyPath] = .unchanged
        block(&state, (), oldState)
    }

    func storageIdentifier(for localId: IdType, in state: State) -> StorageService.StorageIdentifier? {
        state[keyPath: storageIdentifierKeyPath]
    }

    func setStorageIdentifier(_ storageIdentifier: StorageService.StorageIdentifier?, for localId: IdType, in state: inout State) {
        state[keyPath: storageIdentifierKeyPath] = storageIdentifier
    }

    func recordWithUnknownFields(for localId: IdType, in state: State) -> RecordType? {
        state[keyPath: recordWithUnknownFieldsKeyPath]
    }

    func setRecordWithUnknownFields(_ recordWithUnknownFields: RecordType?, for localId: IdType, in state: inout State) {
        state[keyPath: recordWithUnknownFieldsKeyPath] = recordWithUnknownFields
    }

    func recordsWithUnknownFields(in state: State) -> [(IdType, RecordType)] {
        guard let recordWithUnknownFields = state[keyPath: recordWithUnknownFieldsKeyPath] else {
            return []
        }
        return [((), recordWithUnknownFields)]
    }
}

private struct MultipleElementStateUpdater<RecordUpdaterType: StorageServiceRecordUpdater>: StorageServiceStateUpdater where RecordUpdaterType.IdType: Hashable {
    typealias IdType = RecordUpdaterType.IdType
    typealias RecordType = RecordUpdaterType.RecordType
    typealias State = StorageServiceOperation.State

    let recordUpdater: RecordUpdaterType
    private let changeStateKeyPath: WritableKeyPath<State, [IdType: State.ChangeState]>
    private let storageIdentifierKeyPath: WritableKeyPath<State, [IdType: StorageService.StorageIdentifier]>
    private let recordWithUnknownFieldsKeyPath: WritableKeyPath<State, [IdType: RecordType]>

    init(
        recordUpdater: RecordUpdaterType,
        changeState: WritableKeyPath<State, [IdType: State.ChangeState]>,
        storageIdentifier: WritableKeyPath<State, [IdType: StorageService.StorageIdentifier]>,
        recordWithUnknownFields: WritableKeyPath<State, [IdType: RecordType]>
    ) {
        self.recordUpdater = recordUpdater
        self.changeStateKeyPath = changeState
        self.storageIdentifierKeyPath = storageIdentifier
        self.recordWithUnknownFieldsKeyPath = recordWithUnknownFields
    }

    func changeState(for localId: IdType, in state: State) -> State.ChangeState? {
        state[keyPath: changeStateKeyPath][localId]
    }

    func setChangeState(_ changeState: State.ChangeState?, for localId: IdType, in state: inout State) {
        state[keyPath: changeStateKeyPath][localId] = changeState
    }

    func resetAndEnumerateChangeStates(in state: inout State, block: (inout State, IdType, State.ChangeState) -> Void) {
        let oldValue = state[keyPath: changeStateKeyPath]
        state[keyPath: changeStateKeyPath] = [:]
        for (localId, changeState) in oldValue {
            block(&state, localId, changeState)
        }
    }

    func storageIdentifier(for localId: IdType, in state: State) -> StorageService.StorageIdentifier? {
        state[keyPath: storageIdentifierKeyPath][localId]
    }

    func setStorageIdentifier(_ storageIdentifier: StorageService.StorageIdentifier?, for localId: IdType, in state: inout State) {
        state[keyPath: storageIdentifierKeyPath][localId] = storageIdentifier
    }

    func recordWithUnknownFields(for localId: IdType, in state: State) -> RecordType? {
        state[keyPath: recordWithUnknownFieldsKeyPath][localId]
    }

    func setRecordWithUnknownFields(_ recordWithUnknownFields: RecordType?, for localId: IdType, in state: inout State) {
        state[keyPath: recordWithUnknownFieldsKeyPath][localId] = recordWithUnknownFields
    }

    func recordsWithUnknownFields(in state: State) -> [(IdType, RecordType)] {
        state[keyPath: recordWithUnknownFieldsKeyPath].map { $0 }
    }
}

// MARK: - Legacy Decoding

/// Optionally attempts decoding a dictionary as a BidirectionalDictionary,
/// in case it was previously stored in that format.
@propertyWrapper
private struct BidirectionalLegacyDecoding<Value: Codable>: Codable {
    enum BidirectionalDictionaryCodingKeys: String, CodingKey {
        case forwardDictionary
        case backwardDictionary
    }

    var wrappedValue: Value
    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Swift.Decoder) throws {
        do {
            // First, try and decode as if we're just a dictionary.
            wrappedValue = try Value(from: decoder)
        } catch DecodingError.keyNotFound, DecodingError.typeMismatch {
            // If we hit a decoding error, try and decode as if
            // we were a BidirectionalDictionary.
            let bidirectionalContainer = try decoder.container(keyedBy: BidirectionalDictionaryCodingKeys.self)
            wrappedValue = try bidirectionalContainer.decode(Value.self, forKey: .forwardDictionary)
        }
    }

    func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}
