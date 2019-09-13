//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSStorageServiceManager)
class StorageServiceManager: NSObject, StorageServiceManagerProtocol {

    @objc
    static let shared = StorageServiceManager()

    override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            self.registrationStateDidChange()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.registrationStateDidChange),
                name: .RegistrationStateDidChange,
                object: nil
            )
        }
    }

    @objc private func registrationStateDidChange() {
        guard TSAccountManager.sharedInstance().isRegisteredAndReady else { return }

        // Schedule a restore. This will do nothing unless we've never
        // registered a manifest before.
        self.restoreOrCreateManifestIfNecessary()

        // If we have any pending changes since we last launch, back them up now.
        self.backupPendingChanges()
    }

    // MARK: -

    @objc
    func recordPendingDeletions(deletedIds: [AccountId]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        // Schedule a backup to run in the next 10 minutes
        // if one hasn't been scheduled already.
        scheduleBackupIfNecessary()
    }

    @objc
    func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) {
        let operation = StorageServiceOperation.recordPendingDeletions(deletedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        // Schedule a backup to run in the next 10 minutes
        // if one hasn't been scheduled already.
        scheduleBackupIfNecessary()
    }

    @objc
    func recordPendingUpdates(updatedIds: [AccountId]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedIds)
        StorageServiceOperation.operationQueue.addOperation(operation)

        // Schedule a backup to run in the next 10 minutes
        // if one hasn't been scheduled already.
        scheduleBackupIfNecessary()
    }

    @objc
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {
        let operation = StorageServiceOperation.recordPendingUpdates(updatedAddresses)
        StorageServiceOperation.operationQueue.addOperation(operation)

        // Schedule a backup to run in the next 10 minutes
        // if one hasn't been scheduled already.
        scheduleBackupIfNecessary()
    }

    @objc
    func backupPendingChanges() {
        let operation = StorageServiceOperation(mode: .backup)
        StorageServiceOperation.operationQueue.addOperation(operation)
    }

    @objc
    func restoreOrCreateManifestIfNecessary() {
        let operation = StorageServiceOperation(mode: .restoreOrCreate)
        StorageServiceOperation.operationQueue.addOperation(operation)
    }

    // MARK: - Backup Scheduling

    private static var scheduledBackupInterval: TimeInterval = kMinuteInterval * 10
    private var backupTimer: Timer?

    // Schedule a one time backup. By default, this will happen ten
    // minutes after the first pending change is recorded.
    private func scheduleBackupIfNecessary() {
        DispatchQueue.main.async {
            // If we already have a backup scheduled, do nothing
            guard self.backupTimer == nil else { return }

            Logger.info("")

            self.backupTimer = Timer.scheduledTimer(
                timeInterval: StorageServiceManager.scheduledBackupInterval,
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

    static var keyValueStore: SDSKeyValueStore {
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

    fileprivate init(mode: Mode) {
        self.mode = mode
        super.init()
        self.remainingRetries = 4
    }

    // MARK: - Run

    // Called every retry, this is where the bulk of the operation's work should go.
    override public func run() {
        Logger.info("\(mode)")

        // Do nothing until the feature is enabled.
        guard FeatureFlags.socialGraphOnServer else {
            return reportSuccess()
        }

        // We don't have backup keys, do nothing. We'll try a
        // fresh restore once the keys are set.
        guard KeyBackupService.hasLocalKeys else {
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
        var identifierMap: BidirectionalDictionary<AccountId, StorageService.ContactIdentifier> = [:]
        var version: UInt64 = 0

        var updatedRecords: [StorageServiceProtoContactRecord] = []

        databaseStorage.read { transaction in
            pendingChanges = StorageServiceOperation.accountChangeMap(transaction: transaction)
            identifierMap = StorageServiceOperation.accountToIdentifierMap(transaction: transaction)
            version = StorageServiceOperation.manifestVersion(transaction: transaction) ?? 0

            // Build an up-to-date contact record for every pending update
            updatedRecords =
                pendingChanges.lazy.filter { $0.value == .updated }.compactMap { accountId, _ in
                    do {
                        guard let contactIdentifier = identifierMap[accountId] else {
                            // This is a new contact, we need to generate an ID
                            let contactIdentifier = StorageService.ContactIdentifier.generate()
                            identifierMap[accountId] = contactIdentifier

                            let record = try StorageServiceProtoContactRecord.build(
                                for: accountId,
                                contactIdentifier: contactIdentifier,
                                transaction: transaction
                            )

                            // Clear pending changes
                            pendingChanges[accountId] = nil

                            return record
                        }

                        let record = try StorageServiceProtoContactRecord.build(
                            for: accountId,
                            contactIdentifier: contactIdentifier,
                            transaction: transaction
                        )

                        // Clear pending changes
                        pendingChanges[accountId] = nil

                        return record
                    } catch {
                        owsFailDebug("Unexpectedly failed to process changes for account \(error)")
                        // If for some reason we failed, we'll just skip it and try this account again next backup.
                        return nil
                    }
            }
        }

        // Lookup the contact identifier for every pending deletion
        let deletedIdentifiers: [StorageService.ContactIdentifier] =
            pendingChanges.lazy.filter { $0.value == .deleted }.compactMap { accountId, _ in
                // Clear the pending change
                pendingChanges[accountId] = nil

                guard let contactIdentifier = identifierMap[accountId] else {
                    // This contact doesn't exist in our records, it may have been
                    // added and then deleted before a backup occured. We can safely skip it.
                    return nil
                }

                // Remove this contact from the mapping
                identifierMap[accountId] = nil

                return contactIdentifier
        }

        // If we have no pending changes, we have nothing left to do
        guard !deletedIdentifiers.isEmpty || !updatedRecords.isEmpty else {
            return reportSuccess()
        }

        // Bump the manifest version
        version += 1

        let manifestBuilder = StorageServiceProtoManifestRecord.builder(version: version)
        manifestBuilder.setKeys(identifierMap.map { $1.data })

        let manifest: StorageServiceProtoManifestRecord
        do {
            manifest = try manifestBuilder.build()
        } catch {
            return reportError(OWSAssertionError("failed to build proto"))
        }

        StorageService.updateManifest(
            manifest,
            newContacts: updatedRecords,
            deletedContacts: deletedIdentifiers
        ).done(on: .global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                // Successfuly updated, store our changes.
                self.databaseStorage.write { transaction in
                    StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
                    StorageServiceOperation.setAccountChangeMap(pendingChanges, transaction: transaction)
                    StorageServiceOperation.setManifestVersion(version, transaction: transaction)
                    StorageServiceOperation.setAccountToIdentifierMap(identifierMap, transaction: transaction)
                }

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
                // it likely means our keys changed. Create a new manifest with the
                // latest version of our backup key.
                if case .decryptionFailed(let previousManifestVersion) = storageError {
                    return self.createNewManifest(version: previousManifestVersion + 1)
                }

                return self.reportError(storageError)
            }

            self.reportError(OWSAssertionError("received unexpected error when fetching manifest"))
        }.retainUntilComplete()
    }

    private func createNewManifest(version: UInt64) {
        var allContactRecords: [StorageServiceProtoContactRecord] = []
        var identifierMap: BidirectionalDictionary<AccountId, StorageService.ContactIdentifier> = [:]

        databaseStorage.read { transaction in
            SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                if recipient.devices.count > 0 {
                    let contactIdentifier = StorageService.ContactIdentifier.generate()
                    identifierMap[recipient.accountId] = contactIdentifier

                    do {
                        allContactRecords.append(
                            try StorageServiceProtoContactRecord.build(
                                for: recipient.accountId,
                                contactIdentifier: contactIdentifier,
                                transaction: transaction
                            )
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
        manifestBuilder.setKeys(allContactRecords.map { $0.key })

        let manifest: StorageServiceProtoManifestRecord
        do {
            manifest = try manifestBuilder.build()
        } catch {
            return reportError(OWSAssertionError("failed to build proto"))
        }

        StorageService.updateManifest(
            manifest,
            newContacts: allContactRecords,
            deletedContacts: []
        ).done(on: .global()) { conflictingManifest in
            guard let conflictingManifest = conflictingManifest else {
                // Successfuly updated, store our changes.
                self.databaseStorage.write { transaction in
                    StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
                    StorageServiceOperation.setAccountChangeMap([:], transaction: transaction)
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
        var identifierMap: BidirectionalDictionary<AccountId, StorageService.ContactIdentifier> = [:]
        var pendingChanges: [AccountId: ChangeState] = [:]
        var consecutiveConflicts = 0

        databaseStorage.write { transaction in
            identifierMap = StorageServiceOperation.accountToIdentifierMap(transaction: transaction)
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

        // Fetch all the contacts in the new manifest and resolve any conflicts appropriately.
        StorageService.fetchContacts(for: manifest.keys.map { .init(data: $0) }).done(on: .global()) { contacts in
            self.databaseStorage.write { transaction in
                for contact in contacts {
                    switch contact.mergeWithLocalContact(transaction: transaction) {
                    case .invalid:
                        // This contact record was invalid, ignore it.
                        // we'll clear it out in the next backup.
                        break

                    case .needsUpdate(let accountId):
                        // our local version was newer, flag this account as needing a sync
                        pendingChanges[accountId] = .updated

                    case .resolved(let accountId):
                        // update the mapping, this could be a new account
                        identifierMap[accountId] = contact.contactIdentifier
                    }
                }

                StorageServiceOperation.setConsecutiveConflicts(0, transaction: transaction)
                StorageServiceOperation.setAccountChangeMap(pendingChanges, transaction: transaction)
                StorageServiceOperation.setManifestVersion(manifest.version, transaction: transaction)
                StorageServiceOperation.setAccountToIdentifierMap(identifierMap, transaction: transaction)

                if backupAfterSuccess { StorageServiceManager.shared.backupPendingChanges() }

                self.reportSuccess()
            }
        }.catch { error in
            if let storageError = error as? StorageService.StorageError {
                return self.reportError(storageError)
            }

            self.reportError(OWSAssertionError("received unexpected error when fetching contacts"))
        }.retainUntilComplete()
    }

    // MARK: - Accessors

    private static let accountToIdentifierMapKey = "accountToIdentifierMap"
    private static let accountChangeMapKey = "accountChangeMap"
    private static let manifestVersionKey = "manifestVersion"
    private static let consecutiveConflictsKey = "consecutiveConflicts"

    private static func manifestVersion(transaction: SDSAnyReadTransaction) -> UInt64? {
        return keyValueStore.getUInt64(manifestVersionKey, transaction: transaction)
    }

    private static func setManifestVersion( _ verison: UInt64, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setUInt64(verison, key: manifestVersionKey, transaction: transaction)
    }

    private static func accountToIdentifierMap(transaction: SDSAnyReadTransaction) -> BidirectionalDictionary<AccountId, StorageService.ContactIdentifier> {
        guard let anyDictionary = keyValueStore.getObject(accountToIdentifierMapKey, transaction: transaction) as? AnyBidirectionalDictionary,
            let dictionary = BidirectionalDictionary<AccountId, Data>(anyDictionary) else {
            return [:]
        }
        return dictionary.mapValues { .init(data: $0) }
    }

    private static func setAccountToIdentifierMap( _ dictionary: BidirectionalDictionary<AccountId, StorageService.ContactIdentifier>, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setObject(
            AnyBidirectionalDictionary(dictionary.mapValues { $0.data }),
            key: accountToIdentifierMapKey,
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
