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

    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = logTag()
        return queue
    }()

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
                self.restoreOrCreateManifestIfNecessary(authedAccount: .implicit())

                // If we have any pending changes since we last launch, back them up now.
                self.backupPendingChanges(authedAccount: .implicit())
            }
        }
    }

    @objc
    private func willResignActive() {
        // If we have any pending changes, start a back up immediately
        // to try and make sure the service doesn't get stale. If for
        // some reason we aren't able to successfully complete this backup
        // while in the background we'll try again on the next app launch.
        backupPendingChanges(authedAccount: .implicit())
    }

    // MARK: -

    private struct ManagerState {
        var hasPendingCleanup = false

        struct PendingBackup {
            // Ideally, we instead have the entire StorageServiceManager class be instantiated
            // with the necesarry context to make authenticated requests.
            // This is a middle ground between the current world (implicit auth we grab
            // from tsAccountManager) and explicit auth management.
            var authedAccount: AuthedAccount
        }

        var pendingBackup: PendingBackup?
        var pendingBackupTimer: Timer?

        struct PendingRestore {
            var authedAccount: AuthedAccount
            var futures: [Future<Void>]
        }
        var pendingRestore: PendingRestore?

        var pendingMutations = PendingMutations(authedAccount: .implicit())

        /// If set, contains the Error from the most recent restore request. If
        /// it's nil, we've either (a) not yet attempted a restore in this
        /// process; or (b) completed the most recent restore successfully.
        var mostRecentRestoreError: Error?
        var pendingRestoreCompletionFutures = [Future<Void>]()

        var isRunningOperation = false
    }

    private let managerState = AtomicValue(ManagerState(), lock: .init())

    private func updateManagerState(block: (inout ManagerState) -> Void) {
        managerState.map {
            var mutableValue = $0
            block(&mutableValue)
            startNextOperationIfNeeded(&mutableValue)
            return mutableValue
        }
    }

    private func startNextOperationIfNeeded(_ managerState: inout ManagerState) {
        guard !managerState.isRunningOperation else {
            // Already running an operation -- we'll start the next when it finishes.
            return
        }
        guard let (nextOperation, cleanupBlock) = popNextOperation(&managerState) else {
            // There's nothing we need to do, so don't start any operation.
            return
        }
        // Run the operation & check again when it's done.
        managerState.isRunningOperation = true

        let completionOperation = BlockOperation { self.finishOperation(cleanupBlock: cleanupBlock) }
        completionOperation.addDependency(nextOperation)
        operationQueue.addOperations([nextOperation, completionOperation], waitUntilFinished: false)
    }

    private func popNextOperation(_ managerState: inout ManagerState) -> (Operation, ((inout ManagerState) -> Void)?)? {
        if managerState.hasPendingCleanup {
            managerState.hasPendingCleanup = false

            return (StorageServiceOperation(mode: .cleanUpUnknownData), nil)
        }

        if managerState.pendingMutations.hasChanges {
            let pendingMutations = managerState.pendingMutations
            // Keep the old account info around.
            managerState.pendingMutations = PendingMutations(authedAccount: managerState.pendingMutations.authedAccount)

            return (StorageServiceOperation.recordPendingMutations(pendingMutations), nil)
        }

        if let pendingRestore = managerState.pendingRestore {
            managerState.pendingRestore = nil

            Logger.debug("Fetching with \(pendingRestore.futures.count) coalesced request(s).")

            let restoreOperation = StorageServiceOperation(mode: .restoreOrCreate(pendingRestore.authedAccount))
            pendingRestore.futures.forEach {
                $0.resolve(on: SyncScheduler(), with: restoreOperation.promise)
            }
            return (restoreOperation, { $0.mostRecentRestoreError = restoreOperation.failingError })
        }

        if !managerState.pendingRestoreCompletionFutures.isEmpty {
            let pendingRestoreCompletionFutures = managerState.pendingRestoreCompletionFutures
            managerState.pendingRestoreCompletionFutures = []

            let mostRecentRestoreError = managerState.mostRecentRestoreError

            return (BlockOperation {
                pendingRestoreCompletionFutures.forEach {
                    if let mostRecentRestoreError {
                        $0.reject(mostRecentRestoreError)
                    } else {
                        $0.resolve(())
                    }
                }
            }, nil)
        }

        if let pendingBackup = managerState.pendingBackup {
            managerState.pendingBackup = nil

            return (StorageServiceOperation(mode: .backup(pendingBackup.authedAccount)), nil)
        }

        return nil
    }

    private func finishOperation(cleanupBlock: ((inout ManagerState) -> Void)?) {
        updateManagerState { managerState in
            cleanupBlock?(&managerState)
            managerState.isRunningOperation = false
        }
    }

    // MARK: - Pending Mutations

    private func updatePendingMutations(block: (inout PendingMutations) -> Void) {
        updateManagerState { managerState in
            block(&managerState.pendingMutations)

            // If we've made any changes, schedule a backup for the near future. This
            // provides an interval during which pending mutations can be coalesced.
            if managerState.pendingMutations.hasChanges, managerState.pendingBackupTimer == nil {
                managerState.pendingBackupTimer = startBackupTimer()
            }
        }
    }

    @objc
    public func recordPendingUpdates(
        updatedAccountIds: [AccountId],
        authedAccount: AuthedAccount
    ) {
        Logger.info("Recording pending update for account IDs: \(updatedAccountIds)")

        updatePendingMutations {
            $0.updatedAccountIds.formUnion(updatedAccountIds)
            $0.authedAccount = authedAccount.orIfImplicitUse($0.authedAccount)
        }
    }

    @objc
    public func recordPendingUpdates(
        updatedAddresses: [SignalServiceAddress],
        authedAccount: AuthedAccount
    ) {
        Logger.info("Recording pending update for addresses: \(updatedAddresses)")

        updatePendingMutations {
            $0.updatedAddresses.formUnion(updatedAddresses)
            $0.authedAccount = authedAccount.orIfImplicitUse($0.authedAccount)
        }
    }

    @objc
    public func recordPendingUpdates(updatedGroupV1Ids: [Data]) {
        updatePendingMutations { pendingMutations in
            updatedGroupV1Ids.forEach { groupV1Id in
                pendingMutations.mutatedGroupV1Ids[groupV1Id] = .updated
            }
        }
    }

    @objc
    public func recordPendingDeletions(deletedGroupV1Ids: [Data]) {
        updatePendingMutations { pendingMutations in
            deletedGroupV1Ids.forEach { groupV1Id in
                pendingMutations.mutatedGroupV1Ids[groupV1Id] = .deleted
            }
        }
    }

    @objc
    public func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {
        updatePendingMutations { $0.updatedGroupV2MasterKeys.formUnion(updatedGroupV2MasterKeys) }
    }

    @objc
    public func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {
        updatePendingMutations { $0.updatedStoryDistributionListIds.formUnion(updatedStoryDistributionListIds) }
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

        updatePendingMutations { $0.updatedLocalAccount = true }
    }

    // MARK: - Actions

    @objc
    @discardableResult
    public func restoreOrCreateManifestIfNecessary(authedAccount: AuthedAccount) -> AnyPromise {
        let (promise, future) = Promise<Void>.pending()
        updateManagerState { managerState in
            var pendingRestore = managerState.pendingRestore ?? .init(authedAccount: authedAccount, futures: [])
            pendingRestore.futures.append(future)
            pendingRestore.authedAccount = authedAccount.orIfImplicitUse(pendingRestore.authedAccount)
            managerState.pendingRestore = pendingRestore
        }
        return AnyPromise(promise)
    }

    @objc
    public func backupPendingChanges(authedAccount: AuthedAccount) {
        updateManagerState { managerState in
            var pendingBackup = managerState.pendingBackup ?? .init(authedAccount: authedAccount)
            pendingBackup.authedAccount = authedAccount.orIfImplicitUse(pendingBackup.authedAccount)
            managerState.pendingBackup = pendingBackup

            if let pendingBackupTimer = managerState.pendingBackupTimer {
                DispatchQueue.main.async { pendingBackupTimer.invalidate() }
                managerState.pendingBackupTimer = nil
            }
        }
    }

    @objc
    public func waitForPendingRestores() -> AnyPromise {
        return AnyPromise(_waitForPendingRestores())
    }

    private func _waitForPendingRestores() -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()
        updateManagerState { managerState in
            managerState.pendingRestoreCompletionFutures.append(future)
        }
        return promise
    }

    @objc
    public func resetLocalData(transaction: SDSAnyWriteTransaction) {
        Logger.info("Resetting local storage service data.")
        StorageServiceOperation.keyValueStore.removeAll(transaction: transaction)
    }

    private func cleanUpUnknownData() {
        updateManagerState { managerState in
            managerState.hasPendingCleanup = true
        }
    }

    // MARK: - Backup Scheduling

    private static var backupDebounceInterval: TimeInterval = 0.2

    // Schedule a one-time backup. By default, this will happen `backupDebounceInterval`
    // seconds after the first pending change is recorded.
    private func startBackupTimer() -> Timer {
        Logger.info("")

        let timer = Timer(
            timeInterval: StorageServiceManager.backupDebounceInterval,
            target: self,
            selector: #selector(self.backupTimerFired(_:)),
            userInfo: nil,
            repeats: false
        )
        DispatchQueue.main.async {
            RunLoop.current.add(timer, forMode: .default)
        }
        return timer
    }

    @objc
    private func backupTimerFired(_ timer: Timer) {
        AssertIsOnMainThread()

        Logger.info("")

        backupPendingChanges(authedAccount: .implicit())
    }
}

// MARK: - PendingMutations

private struct PendingMutations {
    var updatedAccountIds = Set<AccountId>()
    var updatedAddresses = Set<SignalServiceAddress>()
    var updatedGroupV2MasterKeys = Set<Data>()
    var updatedStoryDistributionListIds = Set<Data>()
    var updatedLocalAccount = false
    var authedAccount: AuthedAccount

    var mutatedGroupV1Ids = [Data: StorageServiceOperation.State.ChangeState]()

    var hasChanges: Bool {
        return (
            updatedLocalAccount
            || !updatedAccountIds.isEmpty
            || !updatedAddresses.isEmpty
            || !updatedGroupV2MasterKeys.isEmpty
            || !updatedStoryDistributionListIds.isEmpty
            || !mutatedGroupV1Ids.isEmpty
        )
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

    fileprivate enum Mode {
        case backup(AuthedAccount)
        case restoreOrCreate(AuthedAccount)
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
        switch mode {
        case .backup(let chatServiceAuth), .restoreOrCreate(let chatServiceAuth):
            if
                chatServiceAuth == .implicit(),
                FeatureFlags.useNewRegistrationFlow,
                !tsAccountManager.isRegisteredAndReady
            {
                Logger.info("Skipping storage service operation with implicit auth during registration.")
                return reportCancelled()
            }
        case .cleanUpUnknownData:
            if FeatureFlags.useNewRegistrationFlow, !tsAccountManager.isRegisteredAndReady {
                return reportCancelled()
            }
        }

        switch mode {
        case .backup(let authedAccount):
            backupPendingChanges(authedAccount: authedAccount)
        case .restoreOrCreate(let authedAccount):
            restoreOrCreateManifestIfNecessary(authedAccount: authedAccount)
        case .cleanUpUnknownData:
            cleanUpUnknownData(authedAccount: .implicit())
        }
    }

    // MARK: - Mark Pending Changes

    fileprivate static func recordPendingMutations(_ pendingMutations: PendingMutations) -> Operation {
        return BlockOperation { databaseStorage.write { recordPendingMutations(pendingMutations, transaction: $0) } }
    }

    private static func recordPendingMutations(_ pendingMutations: PendingMutations, transaction: SDSAnyWriteTransaction) {
        let localAccountId: AccountId?
        if let localAddress = pendingMutations.authedAccount.localUserAddress() {
            localAccountId = OWSAccountIdFinder.accountId(forAddress: localAddress, transaction: transaction)
        } else {
            localAccountId = tsAccountManager.localAccountId(transaction: transaction)
        }

        // Coalesce addresses to account IDs. There may be duplicates among the
        // addresses and account IDs.

        var allAccountIds = Set<AccountId>()

        allAccountIds.formUnion(pendingMutations.updatedAccountIds)

        allAccountIds.formUnion(pendingMutations.updatedAddresses.lazy.map {
            OWSAccountIdFinder.ensureAccountId(forAddress: $0, transaction: transaction)
        })

        // Check if we're updating the local account. If so, remove it so that we
        // don't try to create a contact record for it, but make sure we'll update
        // the account record.

        var updatedLocalAccount = pendingMutations.updatedLocalAccount

        if let localAccountId, allAccountIds.remove(localAccountId) != nil {
            updatedLocalAccount = true
        }

        // Then, update State with all these pending mutations.

        var state = State.current(transaction: transaction)

        Logger.info(
            """
            Recording pending mutations (\
            Account: \(updatedLocalAccount); \
            Contacts: \(allAccountIds.count); \
            GV1: \(pendingMutations.mutatedGroupV1Ids.count); \
            GV2: \(pendingMutations.updatedGroupV2MasterKeys.count); \
            DLists: \(pendingMutations.updatedStoryDistributionListIds.count))
            """
        )

        if updatedLocalAccount {
            state.localAccountChangeState = .updated
        }

        allAccountIds.forEach {
            state.accountIdChangeMap[$0] = .updated
        }

        pendingMutations.mutatedGroupV1Ids.forEach {
            state.groupV1ChangeMap[$0] = $1
        }

        pendingMutations.updatedGroupV2MasterKeys.forEach {
            state.groupV2ChangeMap[$0] = .updated
        }

        pendingMutations.updatedStoryDistributionListIds.forEach {
            state.storyDistributionListChangeMap[$0] = .updated
        }

        state.save(transaction: transaction)
    }

    // MARK: - Backup

    private func backupPendingChanges(authedAccount: AuthedAccount) {
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
                newRecord = recordUpdater.buildRecord(
                    for: localId,
                    unknownFields: unknownFields,
                    transaction: transaction
                )
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

            if let contactUpdater = buildContactUpdater(authedAccount: authedAccount) {
                updateRecords(state: &state, stateUpdater: contactUpdater, transaction: transaction)
            }
            updateRecords(state: &state, stateUpdater: buildGroupV1Updater(), transaction: transaction)
            updateRecords(state: &state, stateUpdater: buildGroupV2Updater(), transaction: transaction)
            updateRecords(state: &state, stateUpdater: buildStoryDistributionListUpdater(), transaction: transaction)

            if let accountUpdater = buildAccountUpdater(
                authedAccount: authedAccount
            ) {
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

        Logger.info(
            """
            Backing up pending changes with proposed manifest version \(state.manifestVersion) (\
            New: \(updatedItems.count), \
            Deleted: \(deletedIdentifiers.count), \
            Invalid/Missing: \(invalidIdentifiers.count), \
            Total: \(state.allIdentifiers.count))
            """
        )

        StorageService.updateManifest(
            manifest,
            newItems: updatedItems,
            deletedIdentifiers: deletedIdentifiers + invalidIdentifiers,
            chatServiceAuth: authedAccount.chatServiceAuth
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
            self.mergeLocalManifest(
                withRemoteManifest: conflictingManifest,
                backupAfterSuccess: true,
                authedAccount: authedAccount
            )
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

    private func restoreOrCreateManifestIfNecessary(
        authedAccount: AuthedAccount
    ) {
        let state: State = databaseStorage.read { State.current(transaction: $0) }

        let greaterThanVersion: UInt64? = {
            // If we've been flagged to refetch the latest manifest,
            // don't specify our current manifest version otherwise
            // the server may return nothing because we've said we
            // already parsed it.
            if state.refetchLatestManifest { return nil }
            return state.manifestVersion
        }()

        StorageService.fetchLatestManifest(
            greaterThanVersion: greaterThanVersion,
            chatServiceAuth: authedAccount.chatServiceAuth
        ).done(on: DispatchQueue.global()) { response in
            switch response {
            case .noExistingManifest:
                // There is no existing manifest, lets create one.
                return self.createNewManifest(
                    version: 1,
                    authedAccount: authedAccount
                )
            case .noNewerManifest:
                // Our manifest version matches the server version, nothing to do here.
                return self.reportSuccess()
            case .latestManifest(let manifest):
                // Our manifest is not the latest, merge in the latest copy.
                self.mergeLocalManifest(
                    withRemoteManifest: manifest,
                    backupAfterSuccess: false,
                    authedAccount: authedAccount
                )
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
                        return self.createNewManifest(
                            version: previousManifestVersion + 1,
                            authedAccount: authedAccount
                        )
                    }

                    Logger.info("Manifest decryption failed, clearing storage service keys.")

                    // If this is a linked device, give up and request the latest storage
                    // service key from the primary device.
                    self.databaseStorage.write { transaction in
                        // Clear out the key, it's no longer valid. This will prevent us
                        // from trying to backup again until the sync response is received.
                        DependenciesBridge.shared.keyBackupService.storeSyncedKey(
                            type: .storageService,
                            data: nil,
                            authedAccount: authedAccount,
                            transaction: transaction.asV2Write
                        )
                        OWSSyncManager.shared.sendKeysSyncRequestMessage(transaction: transaction)
                    }
                }

                return self.reportError(storageError)
            }

            self.reportError(withUndefinedRetry: error)
        }
    }

    private func createNewManifest(
        version: UInt64,
        authedAccount: AuthedAccount
    ) {
        var allItems: [StorageService.StorageItem] = []
        var state = State()

        state.manifestVersion = version

        databaseStorage.read { transaction in
            func createRecord<StateUpdater: StorageServiceStateUpdater>(
                localId: StateUpdater.IdType,
                stateUpdater: StateUpdater
            ) {
                let recordUpdater = stateUpdater.recordUpdater

                let newRecord = recordUpdater.buildRecord(
                    for: localId,
                    unknownFields: nil,
                    transaction: transaction
                )
                guard let newRecord else {
                    return
                }
                let storageItem = recordUpdater.buildStorageItem(for: newRecord)
                stateUpdater.setStorageIdentifier(storageItem.identifier, for: localId, in: &state)
                allItems.append(storageItem)
            }

            let accountUpdater = buildAccountUpdater(authedAccount: authedAccount)
            let contactUpdater = buildContactUpdater(authedAccount: authedAccount)
            SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                if recipient.address.isLocalAddress || authedAccount.isAddressForLocalUser(recipient.address) {
                    guard let accountUpdater else { return }
                    createRecord(localId: (), stateUpdater: accountUpdater)
                } else {
                    guard let contactUpdater else { return }
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
            deleteAllExistingRecords: shouldDeletePreviousRecords,
            chatServiceAuth: authedAccount.chatServiceAuth
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
            self.mergeLocalManifest(
                withRemoteManifest: conflictingManifest,
                backupAfterSuccess: true,
                authedAccount: authedAccount
            )
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    // MARK: - Conflict Resolution

    private func mergeLocalManifest(
        withRemoteManifest manifest: StorageServiceProtoManifestRecord,
        backupAfterSuccess: Bool,
        authedAccount: AuthedAccount
    ) {
        var state: State = databaseStorage.write { transaction in
            var state = State.current(transaction: transaction)

            // Increment our conflict count.
            state.consecutiveConflicts += 1
            state.save(transaction: transaction)

            return state
        }

        // If we've tried many times in a row to resolve conflicts, something weird
        // is happening (potentially a bug on the service or a race with another
        // app). Give up and wait until the next backup runs.
        guard state.consecutiveConflicts <= StorageServiceOperation.maxConsecutiveConflicts else {
            owsFailDebug("unexpectedly have had numerous repeated conflicts")

            // Clear out the consecutive conflicts count so we can try again later.
            databaseStorage.write { transaction in
                state.save(clearConsecutiveConflicts: true, transaction: transaction)
            }

            return reportError(OWSAssertionError("exceeded max consecutive conflicts, creating a new manifest"))
        }

        let allManifestItems: Set<StorageService.StorageIdentifier> = Set(manifest.keys.lazy.map {
            .init(data: $0.data, type: $0.type)
        })

        // Calculate new or updated items by looking up the ids of any items we
        // don't know about locally. Since a new id is always generated after a
        // change, this reflects changes made since the last manifest version.
        var newOrUpdatedItems = Array(allManifestItems.subtracting(state.allIdentifiers))

        // We also want to refetch any identifiers that we didn't know how to parse
        // before but now do know how to parse. These might not have gotten
        // updated, so we need to add them explicitly.
        for (keyType, unknownIdentifiers) in state.unknownIdentifiersTypeMap {
            guard Self.isKnownKeyType(keyType) else { continue }
            newOrUpdatedItems.append(contentsOf: unknownIdentifiers)
        }

        let localKeysCount = state.allIdentifiers.count

        Logger.info(
            """
            Merging with newer remote manifest version \(manifest.version) (\
            New: \(newOrUpdatedItems.count); \
            Remote: \(allManifestItems.count); \
            Local: \(localKeysCount))
            """
        )

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

            return StorageService.fetchItem(
                for: newLocalAccountIdentifier,
                chatServiceAuth: authedAccount.chatServiceAuth
            ).done(on: DispatchQueue.global()) { item in
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

                guard let accountUpdater = self.buildAccountUpdater(
                    authedAccount: authedAccount
                ) else {
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
            // Clean up our unknown identifiers type map to only reflect identifiers
            // that still exist in the manifest. If we find more unknown identifiers in
            // any batch, we'll add them in `fetchAndMergeItemsInBatches`.
            state.unknownIdentifiersTypeMap = state.unknownIdentifiersTypeMap
                .mapValues { unknownIdentifiers in Array(allManifestItems.intersection(unknownIdentifiers)) }
                .filter { (recordType, unknownIdentifiers) in !unknownIdentifiers.isEmpty }

            // Then, fetch the remaining items in the manifest and resolve any conflicts as appropriate.
            let promise: Promise<State> = self.fetchAndMergeItemsInBatches(
                identifiers: newOrUpdatedItems,
                manifest: manifest,
                state: state,
                authedAccount: authedAccount
            )
            return promise
        }.done(on: DispatchQueue.global()) { updatedState in
            var mutableState = updatedState
            self.databaseStorage.write { transaction in
                // Update the manifest version to reflect the remote version we just restored to
                mutableState.manifestVersion = manifest.version

                // We just did a successful manifest fetch and restore, so we no longer need to refetch it
                mutableState.refetchLatestManifest = false

                // We fetched all the previously unknown identifiers, so we don't need to
                // fetch them again in the future unless they're updated.
                mutableState.unknownIdentifiersTypeMap = mutableState.unknownIdentifiersTypeMap
                    .filter { (keyType, _) in !Self.isKnownKeyType(keyType) }

                // Save invalid identifiers to remove during the write operation.
                //
                // We don't remove them immediately because we've already ignored them, and
                // we want to avoid fighting against another device that may put them back
                // when we remove them. Instead, we simply keep track of them so that we
                // can delete them during our next mutation.
                //
                // We may have invalid identifiers for three reasons:
                //
                // (1) We got back an .invalid merge result, meaning we didn't process a
                // storage item. As a result, our local state won't reference it.
                //
                // (2) There are two storage items (with different storage identifiers)
                // whose contents refer to the same thing (eg, group, story). In this case,
                // the latter will replace the former, and the former will be orphaned.
                //
                // (3) The identifier is present in the manifest, but the corresponding
                // item can't be fetched. When this happens, the most likely explanation is
                // that our manifest is out of date. The next time we try to write, we'll
                // get a conflict, merge the latest manifest, see that it no longer
                // references this identifier, and remove it from `invalidIdentifiers`. (In
                // the less common case where the latest manifest does refer to a
                // non-existent identifier, this device will take care of fixing up the
                // manifest to remove the reference.)

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

                let pendingChangesCount = (
                    mutableState.accountIdChangeMap.count
                    + mutableState.groupV1ChangeMap.count
                    + mutableState.groupV2ChangeMap.count
                    + mutableState.storyDistributionListChangeMap.count
                )

                Logger.info(
                    """
                    Successfully merged remote manifest \(manifest.version) (\
                    Pending Updates: \(pendingChangesCount); \
                    Invalid/Missing IDs: \(invalidIdentifierCount); \
                    Orphaned Accounts: \(orphanedAccountCount); \
                    Orphaned GV1: \(orphanedGroupV1Count); \
                    Orphaned GV2: \(orphanedGroupV2Count); \
                    Orphaned DLists: \(orphanedStoryDistributionListCount))
                    """
                )

                mutableState.save(clearConsecutiveConflicts: true, transaction: transaction)

                if backupAfterSuccess {
                    StorageServiceManager.shared.backupPendingChanges(
                        authedAccount: authedAccount
                    )
                }
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
                        return self.createNewManifest(
                            version: manifest.version + 1,
                            authedAccount: authedAccount
                        )
                    }

                    Logger.info("Item decryption failed, clearing storage service keys.")

                    // If this is a linked device, give up and request the latest storage
                    // service key from the primary device.
                    self.databaseStorage.write { transaction in
                        // Clear out the key, it's no longer valid. This will prevent us
                        // from trying to backup again until the sync response is received.
                        DependenciesBridge.shared.keyBackupService.storeSyncedKey(
                            type: .storageService,
                            data: nil,
                            authedAccount: authedAccount,
                            transaction: transaction.asV2Write
                        )
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
        state: State,
        authedAccount: AuthedAccount
    ) -> Promise<State> {
        var remainingItems = identifiers.count
        var mutableState = state
        var promise = Promise.value(())
        for identifierBatch in identifiers.chunked(by: Self.itemsBatchSize) {
            promise = promise.then(on: DispatchQueue.global()) {
                StorageService.fetchItems(
                    for: Array(identifierBatch),
                    chatServiceAuth: authedAccount.chatServiceAuth
                )
            }.done(on: DispatchQueue.global()) { items in
                self.databaseStorage.write { transaction in
                    let contactUpdater = self.buildContactUpdater(authedAccount: authedAccount)
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
                            guard let contactUpdater else {
                                owsFailDebug("Failed to create contact updater; skipping contact record.")
                                continue
                            }
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

                    remainingItems -= identifierBatch.count

                    Logger.info(
                        """
                        Successfully merged remote manifest version \(manifest.version) \
                        from device \(manifest.hasSourceDevice ? String(manifest.sourceDevice) : "(unspecified") (\
                        Identifiers: \(identifierBatch.count); \
                        Items: \(items.count); \
                        Remaining: \(remainingItems))
                        """
                    )

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

    private func cleanUpUnknownData(
        authedAccount: AuthedAccount
    ) {
        databaseStorage.write { transaction in
            self.cleanUpUnknownIdentifiers(transaction: transaction)
            self.cleanUpRecordsWithUnknownFields(
                authedAccount: authedAccount,
                transaction: transaction
            )
            self.cleanUpOrphanedAccounts(transaction: transaction)
        }

        return self.reportSuccess()
    }

    private static func isKnownKeyType(_ keyType: StorageServiceProtoManifestRecordKeyType?) -> Bool {
        switch keyType {
        case .contact:
            return true
        case .groupv1:
            return true
        case .groupv2:
            return true
        case .account:
            return true
        case .storyDistributionList:
            return true
        case .unknown, .UNRECOGNIZED, nil:
            return false
        }
    }

    private func cleanUpUnknownIdentifiers(transaction: SDSAnyWriteTransaction) {
        var state = State.current(transaction: transaction)

        let canParseAnyUnknownIdentifier = state.unknownIdentifiersTypeMap.contains { keyType, unknownIdentifiers in
            guard Self.isKnownKeyType(keyType) else {
                // We don't know this type, so it's not parseable.
                return false
            }
            guard !unknownIdentifiers.isEmpty else {
                // There's no identifiers of this type, so there's nothing to parse.
                return false
            }
            return true
        }

        guard canParseAnyUnknownIdentifier else {
            return
        }

        // We may have learned of new record types. If so, we should refetch the
        // latest manifest so that we can merge these items.
        state.refetchLatestManifest = true

        state.save(transaction: transaction)
    }

    private func cleanUpRecordsWithUnknownFields(
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        var state = State.current(transaction: transaction)

        guard state.unknownFieldLastCheckedAppVersion != appVersion.currentAppVersion4 else {
            return
        }
        state.unknownFieldLastCheckedAppVersion = appVersion.currentAppVersion4

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

            let debugDescription = "\(type(of: stateUpdater.recordUpdater))"
            for (localId, recordWithUnknownFields) in recordsWithUnknownFields {
                guard let storageIdentifier = stateUpdater.storageIdentifier(for: localId, in: state) else {
                    owsFailDebug("Unknown fields: Missing identifier for \(debugDescription)")
                    stateUpdater.setRecordWithUnknownFields(nil, for: localId, in: &state)
                    continue
                }
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

        if let accountUpdater = buildAccountUpdater(authedAccount: authedAccount) {
            mergeRecordsWithUnknownFields(stateUpdater: accountUpdater)
        }
        if let contactUpdater = buildContactUpdater(authedAccount: authedAccount) {
            mergeRecordsWithUnknownFields(stateUpdater: contactUpdater)
        }
        mergeRecordsWithUnknownFields(stateUpdater: buildGroupV1Updater())
        mergeRecordsWithUnknownFields(stateUpdater: buildGroupV2Updater())
        mergeRecordsWithUnknownFields(stateUpdater: buildStoryDistributionListUpdater())

        Logger.info("Resolved unknown fields using manifest version \(state.manifestVersion)")
        state.save(transaction: transaction)
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

        var pendingMutations = PendingMutations(authedAccount: .implicit())
        pendingMutations.updatedAccountIds.formUnion(orphanedAccountIds)
        Self.recordPendingMutations(pendingMutations, transaction: transaction)
    }

    // MARK: - Record Merge

    private func mergeRecord<StateUpdater: StorageServiceStateUpdater>(
        _ record: StateUpdater.RecordType,
        identifier: StorageService.StorageIdentifier,
        state: inout State,
        stateUpdater: StateUpdater,
        transaction: SDSAnyWriteTransaction
    ) {
        let mergeResult = stateUpdater.recordUpdater.mergeRecord(
            record,
            transaction: transaction
        )
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

    private func buildAccountUpdater(
        authedAccount: AuthedAccount
    ) -> SingleElementStateUpdater<StorageServiceAccountRecordUpdater>? {
        let localAddress: SignalServiceAddress? =
            authedAccount.localUserAddress() ?? TSAccountManager.localAddress

        guard
            let localAddress = localAddress,
            let localAci = localAddress.uuid
        else {
            owsFailDebug("Can't update local account without local address and ACI.")
            return nil
        }

        return SingleElementStateUpdater(
            recordUpdater: StorageServiceAccountRecordUpdater(
                localAddress: localAddress,
                localAci: localAci,
                authedAccount: authedAccount,
                changePhoneNumber: changePhoneNumber,
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

    private func buildContactUpdater(
        authedAccount: AuthedAccount
    ) -> MultipleElementStateUpdater<StorageServiceContactRecordUpdater>? {
        let localAddress = authedAccount.localUserAddress() ?? TSAccountManager.localAddress

        guard let localAddress else {
            owsFailDebug("Can't update contact record without local address and ACI.")
            return nil
        }

        return MultipleElementStateUpdater(
            recordUpdater: StorageServiceContactRecordUpdater(
                localAddress: localAddress,
                authedAccount: authedAccount,
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

        /// The app version from the last time we checked unknown fields. We can
        /// only transition unknown fields to known fields via an update, so we only
        /// need to check once per app version.
        fileprivate var unknownFieldLastCheckedAppVersion: String?

        enum ChangeState: Int, Codable {
            case unchanged = 0
            case updated = 1

            /// This is mostly vestigial, but even when we no longer assign this status
            /// in new versions of the application, we'll still need to support reading
            /// it (for times when it was written by prior versions of the application).
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
