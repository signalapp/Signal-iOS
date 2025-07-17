//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
public import LibSignalClient

public enum IdentityManagerError: Error, IsRetryableProvider {
    case identityKeyMismatchForOutgoingMessage

    public var isRetryableProvider: Bool { false }
}

public protocol OWSIdentityManager {
    func libSignalStore(for identity: OWSIdentity, tx: DBReadTransaction) throws -> IdentityStore
    func groupContainsUnverifiedMember(_ groupUniqueID: String, tx: DBReadTransaction) -> Bool
    func fireIdentityStateChangeNotification(after tx: DBWriteTransaction)

    func recipientIdentity(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSRecipientIdentity?
    func recipientIdentity(for recipientUniqueId: RecipientUniqueId, tx: DBReadTransaction) -> OWSRecipientIdentity?
    func removeRecipientIdentity(for recipientUniqueId: RecipientUniqueId, tx: DBWriteTransaction)

    func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair?
    func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction)
    func wipeIdentityKeysFromFailedProvisioning(tx: DBWriteTransaction)

    func identityKey(for address: SignalServiceAddress, tx: DBReadTransaction) -> Data?
    func identityKey(for serviceId: ServiceId, tx: DBReadTransaction) throws -> IdentityKey?

    @discardableResult
    func saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, tx: DBWriteTransaction) -> Result<IdentityChange, RecipientIdError>

    func insertIdentityChangeInfoMessage(for serviceId: ServiceId, wasIdentityVerified: Bool, tx: DBWriteTransaction)
    func insertSessionSwitchoverEvent(for recipient: SignalRecipient, phoneNumber: String?, tx: DBWriteTransaction)
    func mergeRecipient(_ recipient: SignalRecipient, into targetRecipient: SignalRecipient, tx: DBWriteTransaction)

    func untrustedIdentityForSending(
        to address: SignalServiceAddress,
        untrustedThreshold: Date?,
        tx: DBReadTransaction
    ) -> OWSRecipientIdentity?

    func tryToSyncQueuedVerificationStates()

    func verificationState(for address: SignalServiceAddress, tx: DBReadTransaction) -> VerificationState
    func setVerificationState(
        _ verificationState: VerificationState,
        of identityKey: Data,
        for address: SignalServiceAddress,
        isUserInitiatedChange: Bool,
        tx: DBWriteTransaction
    ) -> ChangeVerificationStateResult

    func processIncomingVerifiedProto(_ verified: SSKProtoVerified, tx: DBWriteTransaction) throws

    func shouldSharePhoneNumber(with serviceId: ServiceId, tx: DBReadTransaction) -> Bool
    func setShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction)
    func clearShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction)
    func clearShouldSharePhoneNumberForEveryone(tx: DBWriteTransaction)

    func batchUpdateIdentityKeys(for serviceIds: [ServiceId]) async throws
}

extension OWSIdentityManager {
    @discardableResult
    public func saveIdentityKey(_ identityKey: IdentityKey, for serviceId: ServiceId, tx: DBWriteTransaction) -> Result<IdentityChange, RecipientIdError> {
        return saveIdentityKey(identityKey.publicKey.keyBytes, for: serviceId, tx: tx)
    }
}

public enum TSMessageDirection {
    case incoming
    case outgoing
}

public enum ChangeVerificationStateResult {
    case error
    case redundant
    case success
}

private extension TSMessageDirection {
    init(_ direction: Direction) {
        switch direction {
        case .receiving:
            self = .incoming
        case .sending:
            self = .outgoing
        }
    }
}

extension OWSIdentity: CustomStringConvertible {
    public var description: String {
        switch self {
        case .aci:
            return "ACI"
        case .pni:
            return "PNI"
        }
    }
}

public class IdentityStore: IdentityKeyStore {
    private let identityManager: OWSIdentityManagerImpl
    private let identityKeyPair: IdentityKeyPair
    private let fetchLocalRegistrationId: (DBWriteTransaction) -> UInt32

    fileprivate init(
        identityManager: OWSIdentityManagerImpl,
        identityKeyPair: IdentityKeyPair,
        fetchLocalRegistrationId: @escaping (DBWriteTransaction) -> UInt32
    ) {
        self.identityManager = identityManager
        self.identityKeyPair = identityKeyPair
        self.fetchLocalRegistrationId = fetchLocalRegistrationId
    }

    public func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        return identityKeyPair
    }

    public func localRegistrationId(context: StoreContext) throws -> UInt32 {
        return fetchLocalRegistrationId(context.asTransaction)
    }

    public func saveIdentity(
        _ identityKey: IdentityKey,
        for address: ProtocolAddress,
        context: StoreContext
    ) throws -> IdentityChange {
        try identityManager.saveIdentityKey(
            identityKey,
            for: address.serviceId,
            tx: context.asTransaction
        ).get()
    }

    public func isTrustedIdentity(
        _ identityKey: IdentityKey,
        for address: ProtocolAddress,
        direction: Direction,
        context: StoreContext
    ) throws -> Bool {
        return try identityManager.isTrustedIdentityKey(
            identityKey,
            serviceId: address.serviceId,
            direction: TSMessageDirection(direction),
            tx: context.asTransaction
        )
    }

    public func identity(for address: ProtocolAddress, context: StoreContext) throws -> LibSignalClient.IdentityKey? {
        return try identityManager.identityKey(for: address.serviceId, tx: context.asTransaction)
    }
}

extension NSNotification.Name {
    // This notification will be fired whenever identities are created
    // or their verification state changes.
    public static let identityStateDidChange = Notification.Name("kNSNotificationNameIdentityStateDidChange")
}

extension OWSIdentityManagerImpl {
    public enum Constants {
        // The canonical key includes 32 bytes of identity material plus one byte specifying the key type
        static let identityKeyLength = 33

        // Cryptographic operations do not use the "type" byte of the identity key, so, for legacy reasons we store just
        // the identity material.
        fileprivate static let storedIdentityKeyLength = 32

        /// Don't trust an identity for sending to unless they've been around for at least this long.
        public static let defaultUntrustedInterval: TimeInterval = 5
    }
}

private extension OWSIdentity {
    var persistenceKey: String {
        switch self {
        case .aci:
            return "TSStorageManagerIdentityKeyStoreIdentityKey"
        case .pni:
            return "TSStorageManagerIdentityKeyStorePNIIdentityKey"
        }
    }
}

extension OWSIdentityManager {
    func generateNewIdentityKeyPair() -> ECKeyPair {
        ECKeyPair.generateKeyPair()
    }
}

public class OWSIdentityManagerImpl: OWSIdentityManager {
    private let aciProtocolStore: SignalProtocolStore
    private let appReadiness: AppReadiness
    private let db: any DB
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let networkManager: NetworkManager
    private let notificationPresenter: any NotificationPresenter
    private let ownIdentityKeyValueStore: KeyValueStore
    private let pniProtocolStore: SignalProtocolStore
    private let profileManager: ProfileManager
    private let queuedVerificationStateSyncMessagesKeyValueStore: KeyValueStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let recipientFetcher: RecipientFetcher
    private let recipientIdFinder: RecipientIdFinder
    private let shareMyPhoneNumberStore: KeyValueStore
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager

    public init(
        aciProtocolStore: SignalProtocolStore,
        appReadiness: AppReadiness,
        db: any DB,
        messageSenderJobQueue: MessageSenderJobQueue,
        networkManager: NetworkManager,
        notificationPresenter: any NotificationPresenter,
        pniProtocolStore: SignalProtocolStore,
        profileManager: ProfileManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        recipientIdFinder: RecipientIdFinder,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager
    ) {
        self.aciProtocolStore = aciProtocolStore
        self.appReadiness = appReadiness
        self.db = db
        self.messageSenderJobQueue = messageSenderJobQueue
        self.networkManager = networkManager
        self.notificationPresenter = notificationPresenter
        self.ownIdentityKeyValueStore = KeyValueStore(
            collection: "TSStorageManagerIdentityKeyStoreCollection"
        )
        self.pniProtocolStore = pniProtocolStore
        self.profileManager = profileManager
        self.queuedVerificationStateSyncMessagesKeyValueStore = KeyValueStore(
            collection: "OWSIdentityManager_QueuedVerificationStateSyncMessages"
        )
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.recipientIdFinder = recipientIdFinder
        self.shareMyPhoneNumberStore = KeyValueStore(
            collection: "OWSIdentityManager.shareMyPhoneNumberStore"
        )
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager

        SwiftSingletons.register(self)
    }

    public func libSignalStore(for identity: OWSIdentity, tx: DBReadTransaction) throws -> IdentityStore {
        guard let identityKeyPair = self.identityKeyPair(for: identity, tx: tx) else {
            throw OWSAssertionError("no identity key pair for \(identity)")
        }
        return IdentityStore(
            identityManager: self,
            identityKeyPair: identityKeyPair.identityKeyPair,
            fetchLocalRegistrationId: { [tsAccountManager] in
                switch identity {
                case .aci:
                    return tsAccountManager.getOrGenerateAciRegistrationId(tx: $0)
                case .pni:
                    return tsAccountManager.getOrGeneratePniRegistrationId(tx: $0)
                }
            }
        )
    }

    public func groupContainsUnverifiedMember(_ groupUniqueID: String, tx: DBReadTransaction) -> Bool {
        return OWSRecipientIdentity.groupContainsUnverifiedMember(groupUniqueID, transaction: tx)
    }

    public func fireIdentityStateChangeNotification(after tx: DBWriteTransaction) {
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .identityStateDidChange, object: nil)
        }
    }

    // MARK: - Fetching

    public func recipientIdentity(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSRecipientIdentity? {
        guard let recipientIdResult = recipientIdFinder.recipientUniqueId(for: address, tx: tx) else {
            return nil
        }
        switch recipientIdResult {
        case .failure(.mustNotUsePniBecauseAciExists):
            // If we pretend as though this identity doesn't exist, we'll get an error
            // when we try to send a message, we'll retry, and then we'll correctly
            // send to the ACI.
            return nil
        case .success(let recipientUniqueId):
            return recipientIdentity(for: recipientUniqueId, tx: tx)
        }
    }

    public func recipientIdentity(for recipientUniqueId: RecipientUniqueId, tx: DBReadTransaction) -> OWSRecipientIdentity? {
        return OWSRecipientIdentity.anyFetch(uniqueId: recipientUniqueId, transaction: tx)
    }

    public func removeRecipientIdentity(for recipientUniqueId: RecipientUniqueId, tx: DBWriteTransaction) {
        recipientIdentity(for: recipientUniqueId, tx: tx)?.anyRemove(transaction: tx)
    }

    // MARK: - Local Identity

    public func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair? {
        return ownIdentityKeyValueStore.getObject(identity.persistenceKey, ofClass: ECKeyPair.self, transaction: tx)
    }

    public func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) {
        // Under no circumstances may we *clear* our *ACI* identity key.
        owsPrecondition(keyPair != nil || identity != .aci)
        ownIdentityKeyValueStore.setObject(keyPair, key: identity.persistenceKey, transaction: tx)
    }

    public func wipeIdentityKeysFromFailedProvisioning(tx: DBWriteTransaction) {
        ownIdentityKeyValueStore.removeValue(forKey: OWSIdentity.aci.persistenceKey, transaction: tx)
        ownIdentityKeyValueStore.removeValue(forKey: OWSIdentity.pni.persistenceKey, transaction: tx)
    }

    // MARK: - Remote Identity Keys

    public func identityKey(for address: SignalServiceAddress, tx: DBReadTransaction) -> Data? {
        switch recipientIdFinder.recipientUniqueId(for: address, tx: tx) {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            return nil
        case .some(.success(let recipientUniqueId)):
            return _identityKey(for: recipientUniqueId, tx: tx)
        }
    }

    public func identityKey(for serviceId: ServiceId, tx: DBReadTransaction) throws -> IdentityKey? {
        guard let recipientIdResult = recipientIdFinder.recipientUniqueId(for: serviceId, tx: tx) else {
            return nil
        }
        guard let keyData = try _identityKey(for: recipientIdResult.get(), tx: tx) else { return nil }
        return try IdentityKey(publicKey: PublicKey(keyData: keyData))
    }

    private func _identityKey(for recipientUniqueId: RecipientUniqueId, tx: DBReadTransaction) -> Data? {
        owsAssertDebug(!recipientUniqueId.isEmpty)
        return OWSRecipientIdentity.anyFetch(uniqueId: recipientUniqueId, transaction: tx)?.identityKey
    }

    @discardableResult
    public func saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, tx: DBWriteTransaction) -> Result<IdentityChange, RecipientIdError> {
        let recipientIdResult = recipientIdFinder.ensureRecipientUniqueId(for: serviceId, tx: tx)
        return recipientIdResult.map({ _saveIdentityKey(identityKey, for: serviceId, recipientUniqueId: $0, tx: tx) })
    }

    private func _saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, recipientUniqueId: RecipientUniqueId, tx: DBWriteTransaction) -> IdentityChange {
        owsAssertDebug(identityKey.count == Constants.storedIdentityKeyLength)

        let existingIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientUniqueId, transaction: tx)
        guard let existingIdentity else {
            Logger.info("Saving first-use identity for \(serviceId)")
            OWSRecipientIdentity(
                uniqueId: recipientUniqueId,
                identityKey: identityKey,
                isFirstKnownKey: true,
                createdAt: Date(),
                verificationState: .default
            ).anyInsert(transaction: tx)
            // Cancel any pending verification state sync messages for this recipient.
            clearSyncMessage(for: recipientUniqueId, tx: tx)
            fireIdentityStateChangeNotification(after: tx)
            storageServiceManager.recordPendingUpdates(updatedRecipientUniqueIds: [recipientUniqueId])
            return .newOrUnchanged
        }

        guard existingIdentity.identityKey != identityKey else {
            return .newOrUnchanged
        }

        let verificationState: VerificationState
        switch VerificationState(existingIdentity.verificationState) {
        case .implicit(isAcknowledged: _):
            verificationState = .implicit(isAcknowledged: false)
        case .verified, .noLongerVerified:
            verificationState = .noLongerVerified
        }
        Logger.info("Saving new identity for \(serviceId): \(existingIdentity.verificationState) -> \(verificationState)")
        insertIdentityChangeInfoMessage(for: serviceId, wasIdentityVerified: existingIdentity.wasIdentityVerified, tx: tx)
        OWSRecipientIdentity(
            uniqueId: recipientUniqueId,
            identityKey: identityKey,
            isFirstKnownKey: false,
            createdAt: Date(),
            verificationState: verificationState.rawValue
        ).anyUpsert(transaction: tx)
        aciProtocolStore.sessionStore.archiveAllSessions(for: serviceId, tx: tx)
        // Cancel any pending verification state sync messages for this recipient.
        clearSyncMessage(for: recipientUniqueId, tx: tx)
        storageServiceManager.recordPendingUpdates(updatedRecipientUniqueIds: [recipientUniqueId])
        return .replacedExisting
    }

    public func insertIdentityChangeInfoMessage(
        for serviceId: ServiceId,
        wasIdentityVerified: Bool,
        tx: DBWriteTransaction
    ) {
        let contactThread = TSContactThread.getOrCreateThread(
            withContactAddress: SignalServiceAddress(serviceId),
            transaction: tx
        )
        let contactThreadMessage: TSErrorMessage = .nonblockingIdentityChange(
            thread: contactThread,
            address: SignalServiceAddress(serviceId),
            wasIdentityVerified: wasIdentityVerified
        )
        contactThreadMessage.anyInsert(transaction: tx)

        for groupThread in TSGroupThread.groupThreads(with: SignalServiceAddress(serviceId), transaction: tx) {
            TSErrorMessage.nonblockingIdentityChange(
                thread: groupThread,
                address: SignalServiceAddress(serviceId),
                wasIdentityVerified: wasIdentityVerified
            ).anyInsert(transaction: tx)
        }

        notificationPresenter.notifyUser(forErrorMessage: contactThreadMessage, thread: contactThread, transaction: tx)
        fireIdentityStateChangeNotification(after: tx)
    }

    public func insertSessionSwitchoverEvent(
        for recipient: SignalRecipient,
        phoneNumber: String?,
        tx: DBWriteTransaction
    ) {
        guard let contactThread = TSContactThread.getWithContactAddress(recipient.address, transaction: tx) else {
            return
        }
        let sessionSwitchoverEvent: TSInfoMessage = .makeForSessionSwitchover(
            contactThread: contactThread,
            phoneNumber: phoneNumber
        )
        sessionSwitchoverEvent.anyInsert(transaction: tx)
    }

    public func mergeRecipient(_ recipient: SignalRecipient, into targetRecipient: SignalRecipient, tx: DBWriteTransaction) {
        let recipientPair = MergePair(fromValue: recipient, intoValue: targetRecipient)
        let recipientIdentity = recipientPair.map {
            OWSRecipientIdentity.anyFetch(uniqueId: $0.uniqueId, transaction: tx)
        }
        guard let fromValue = recipientIdentity.fromValue else {
            return
        }
        if recipientIdentity.intoValue == nil {
            OWSRecipientIdentity(
                uniqueId: targetRecipient.uniqueId,
                identityKey: fromValue.identityKey,
                isFirstKnownKey: fromValue.isFirstKnownKey,
                createdAt: fromValue.createdAt,
                verificationState: fromValue.verificationState
            ).anyInsert(transaction: tx)
        }
        fromValue.anyRemove(transaction: tx)
    }

    // MARK: - Trust

    public func untrustedIdentityForSending(
        to address: SignalServiceAddress,
        untrustedThreshold: Date?,
        tx: DBReadTransaction
    ) -> OWSRecipientIdentity? {
        let recipientIdentity = recipientIdentity(for: address, tx: tx)
        let isTrusted = isIdentityKeyTrustedForSending(
            address: address,
            recipientIdentity: recipientIdentity,
            untrustedThreshold: untrustedThreshold,
            tx: tx
        )
        return isTrusted ? nil : recipientIdentity
    }

    private func isIdentityKeyTrustedForSending(
        address: SignalServiceAddress,
        recipientIdentity: OWSRecipientIdentity?,
        untrustedThreshold: Date?,
        tx: DBReadTransaction
    ) -> Bool {
        owsAssertDebug(address.isValid)

        if address.isLocalAddress {
            guard let recipientIdentity else {
                // Trust on first use.
                return true
            }
            return isTrustedLocalKey(recipientIdentity.identityKey, tx: tx)
        }

        return canSend(to: recipientIdentity, untrustedThreshold: untrustedThreshold)
    }

    func isTrustedIdentityKey(
        _ identityKey: IdentityKey,
        serviceId: ServiceId,
        direction: TSMessageDirection,
        tx: DBReadTransaction
    ) throws -> Bool {
        let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
        if localIdentifiers?.aci == serviceId {
            return isTrustedLocalKey(identityKey.publicKey.keyBytes, tx: tx)
        }

        switch direction {
        case .incoming:
            return true
        case .outgoing:
            guard let recipientUniqueId = try recipientIdFinder.recipientUniqueId(for: serviceId, tx: tx)?.get() else {
                owsFailDebug("Couldn't find recipientUniqueId for outgoing message.")
                return false
            }
            let recipientIdentity = OWSRecipientIdentity.anyFetch(
                uniqueId: recipientUniqueId,
                transaction: tx
            )
            if let recipientIdentity, recipientIdentity.identityKey != identityKey.publicKey.keyBytes {
                Logger.warn("Key mismatch for \(serviceId)")
                throw IdentityManagerError.identityKeyMismatchForOutgoingMessage
            }
            return canSend(to: recipientIdentity, untrustedThreshold: nil)
        }
    }

    private func isTrustedLocalKey(_ identityKey: Data, tx: DBReadTransaction) -> Bool {
        let localIdentityKeyPair = identityKeyPair(for: .aci, tx: tx)
        guard localIdentityKeyPair?.publicKey == identityKey else {
            owsFailDebug("Wrong identity key for local account.")
            return false
        }
        return true
    }

    private func canSend(to recipientIdentity: OWSRecipientIdentity?, untrustedThreshold: Date?) -> Bool {
        guard let recipientIdentity else {
            // Trust on first use.
            return true
        }

        if recipientIdentity.isFirstKnownKey {
            return true
        }

        switch recipientIdentity.verificationState {
        case .default:
            // This user has never been explicitly verified, but we still want to check
            // if the identity key is one we newly learned about to give the local user
            // time to ensure they wish to send. If it has been created in the last N
            // seconds, we'll treat it as untrusted so sends fail. This is a best
            // effort, and we'll continue to allow sending to the user after the "new"
            // window elapses without any explicit action from the local user.
            let untrustedThreshold = untrustedThreshold ?? Date(timeIntervalSinceNow: -Constants.defaultUntrustedInterval)
            guard recipientIdentity.createdAt <= untrustedThreshold else {
                Logger.warn("Not trusting new identity for \(recipientIdentity.uniqueId)")
                return false
            }
            return true
        case .defaultAcknowledged:
            return true
        case .verified:
            return true
        case .noLongerVerified:
            // This user was previously verified and their key has changed. We will not trust
            // them again until the user explicitly acknowledges the key change.
            Logger.warn("Not trusting no-longer-verified identity for \(recipientIdentity.uniqueId)")
            return false
        }
    }

    // MARK: - Sync Messages

    private func enqueueSyncMessage(for recipientUniqueId: RecipientUniqueId, tx: DBWriteTransaction) {
        queuedVerificationStateSyncMessagesKeyValueStore.setObject(true, key: recipientUniqueId, transaction: tx)
        DispatchQueue.main.async { self.tryToSyncQueuedVerificationStates() }
    }

    private func clearSyncMessage(for key: String, tx: DBWriteTransaction) {
        queuedVerificationStateSyncMessagesKeyValueStore.setObject(nil, key: key, transaction: tx)
    }

    public func tryToSyncQueuedVerificationStates() {
        AssertIsOnMainThread()
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            DispatchQueue.global().async { self.syncQueuedVerificationStates() }
        }
    }

    private func syncQueuedVerificationStates() {
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }
        guard let thread = TSContactThread.getOrCreateLocalThreadWithSneakyTransaction() else {
            owsFailDebug("Missing thread.")
            return
        }
        let allKeys = db.read { tx in queuedVerificationStateSyncMessagesKeyValueStore.allKeys(transaction: tx) }
        // We expect very few keys in practice, and each key triggers multiple
        // database write transactions. If we do end up with thousands of keys,
        // using a separate transaction avoids long blocks.
        for key in allKeys {
            let syncMessage = db.write { (tx) -> OWSVerificationStateSyncMessage? in
                guard let syncMessage = buildVerificationStateSyncMessage(for: key, localThread: thread, tx: tx) else {
                    queuedVerificationStateSyncMessagesKeyValueStore.removeValue(forKey: key, transaction: tx)
                    return nil
                }
                return syncMessage
            }
            guard let syncMessage else {
                continue
            }
            sendVerificationStateSyncMessage(for: key, message: syncMessage)
        }
    }

    private func buildVerificationStateSyncMessage(
        for key: String,
        localThread: TSContactThread,
        tx: DBReadTransaction
    ) -> OWSVerificationStateSyncMessage? {
        let value: Any? = queuedVerificationStateSyncMessagesKeyValueStore.getObject(
            key,
            ofClasses: [NSNumber.self, NSString.self, SignalServiceAddress.self],
            transaction: tx
        )
        guard let value else {
            return nil
        }
        let recipientUniqueId: RecipientUniqueId
        switch value {
        case let numberValue as NSNumber:
            guard numberValue.boolValue else {
                return nil
            }
            recipientUniqueId = key
        case is SignalServiceAddress:
            recipientUniqueId = key
        case let stringValue as NSString:
            // Previously, we stored phone numbers in this KV store.
            let address = SignalServiceAddress.legacyAddress(serviceId: nil, phoneNumber: stringValue as String)
            guard let recipientUniqueId_ = try? recipientIdFinder.recipientUniqueId(for: address, tx: tx)?.get() else {
                return nil
            }
            recipientUniqueId = recipientUniqueId_
        default:
            return nil
        }

        if recipientUniqueId.isEmpty {
            return nil
        }

        let recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientUniqueId, transaction: tx)

        guard let recipientIdentity else {
            owsFailDebug("Couldn't load recipient identity for \(recipientUniqueId)")
            return nil
        }

        guard let identityKey = try? recipientIdentity.identityKeyObject else {
            owsFailDebug("Invalid recipient identity key for \(recipientUniqueId)")
            return nil
        }

        // We don't want to sync "no longer verified" state. Other
        // clients can figure this out from the /profile/ endpoint, and
        // this can cause data loss as a user's devices overwrite each
        // other's verification.
        if recipientIdentity.verificationState == .noLongerVerified {
            owsFailDebug("Queue verification state is invalid for \(recipientUniqueId)")
            return nil
        }

        guard let recipient = recipientDatabaseTable.fetchRecipient(uniqueId: recipientUniqueId, tx: tx) else {
            return nil
        }

        return OWSVerificationStateSyncMessage(
            localThread: localThread,
            verificationState: recipientIdentity.verificationState,
            identityKey: identityKey.serialize(),
            verificationForRecipientAddress: recipient.address,
            transaction: tx
        )
    }

    private func sendVerificationStateSyncMessage(for recipientUniqueId: RecipientUniqueId, message: OWSVerificationStateSyncMessage) {
        let address = message.verificationForRecipientAddress
        let contactThread = TSContactThread.getOrCreateThread(contactAddress: address)

        // DURABLE CLEANUP - we could replace the custom durability logic in this class
        // with a durable JobQueue.
        let nullMessagePromise = db.write { tx in
            // Send null message to appear as though we're sending a normal message to cover the sync message sent
            // subsequently
            let nullMessage = OWSOutgoingNullMessage(
                contactThread: contactThread,
                verificationStateSyncMessage: message,
                transaction: tx
            )
            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: nullMessage
            )
            return messageSenderJobQueue.add(
                .promise,
                message: preparedMessage,
                limitToCurrentProcessLifetime: true,
                transaction: tx
            )
        }

        nullMessagePromise.done(on: DispatchQueue.global()) {
            Logger.info("Successfully sent verification state NullMessage")
            let syncMessagePromise = self.db.write { tx in
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: message
                )
                return self.messageSenderJobQueue.add(
                    .promise,
                    message: preparedMessage,
                    limitToCurrentProcessLifetime: true,
                    transaction: tx
                )
            }
            syncMessagePromise.done(on: DispatchQueue.global()) {
                Logger.info("Successfully sent verification state sync message")
                self.db.write { tx in self.clearSyncMessage(for: recipientUniqueId, tx: tx) }
            }.catch(on: DispatchQueue.global()) { error in
                Logger.error("Failed to send verification state sync message: \(error)")
            }
        }.catch(on: DispatchQueue.global()) { error in
            Logger.error("Failed to send verification state NullMessage: \(error)")
            if error is MessageSenderNoSuchSignalRecipientError {
                Logger.info("Removing retries for syncing verification for unregistered user: \(address)")
                self.db.write { tx in self.clearSyncMessage(for: recipientUniqueId, tx: tx) }
            }
        }
    }

    // MARK: - Verification

    public func verificationState(for address: SignalServiceAddress, tx: DBReadTransaction) -> VerificationState {
        return VerificationState(recipientIdentity(for: address, tx: tx)?.verificationState ?? .default)
    }

    public func setVerificationState(
        _ verificationState: VerificationState,
        of identityKey: Data,
        for address: SignalServiceAddress,
        isUserInitiatedChange: Bool,
        tx: DBWriteTransaction
    ) -> ChangeVerificationStateResult {
        owsAssertDebug(identityKey.count == Constants.storedIdentityKeyLength)

        let recipient = OWSAccountIdFinder.ensureRecipient(forAddress: address, transaction: tx)
        let recipientUniqueId = recipient.uniqueId
        let recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientUniqueId, transaction: tx)
        guard let recipientIdentity else {
            owsFailDebug("Missing OWSRecipientIdentity.")
            return .error
        }

        guard recipientIdentity.identityKey == identityKey else {
            Logger.warn("Can't change verification state for outdated identity key")
            return .error
        }

        let oldVerificationState = VerificationState(recipientIdentity.verificationState)
        if oldVerificationState == verificationState {
            return .redundant
        }

        // If we're sending to a Pni, the identity key might change. If that
        // happens, we can acknowledge it, but we can't mark it as verified.
        if recipient.pni != nil, recipient.aciString == nil {
            switch verificationState {
            case .verified, .noLongerVerified, .implicit(isAcknowledged: false):
                owsFailDebug("Can't mark Pni recipient as verified/no longer verified.")
                return .error
            case .implicit(isAcknowledged: true):
                break
            }
        }

        Logger.info("setVerificationState for \(recipientUniqueId): \(recipientIdentity.verificationState) -> \(verificationState)")
        recipientIdentity.verificationState = verificationState.rawValue
        recipientIdentity.anyOverwritingUpdate(transaction: tx)

        switch (oldVerificationState, verificationState) {
        case (.implicit, .implicit):
            // We're only changing `isAcknowledged`, and that doesn't impact Storage
            // Service, sync messages, or chat events.
            break
        default:
            if isUserInitiatedChange {
                switch verificationState {
                case .verified:
                    // If you mark someone as verified on this device, add them
                    // to the profile whitelist so they become a "Signal
                    // Connection". (Other devices will learn about this via
                    // Storage Service like normal.)
                    profileManager.addUser(
                        toProfileWhitelist: recipient.address,
                        userProfileWriter: .localUser,
                        transaction: tx
                    )
                case .noLongerVerified, .implicit:
                    break
                }

                saveChangeMessages(for: recipient, verificationState: verificationState, isLocalChange: true, tx: tx)
                enqueueSyncMessage(for: recipientUniqueId, tx: tx)
            } else {
                // Cancel any pending verification state sync messages for this recipient.
                clearSyncMessage(for: recipientUniqueId, tx: tx)
            }
            // Verification state has changed, so notify storage service.
            storageServiceManager.recordPendingUpdates(updatedRecipientUniqueIds: [recipientUniqueId])
        }
        fireIdentityStateChangeNotification(after: tx)
        return .success
    }

    // MARK: - Verified

    public func processIncomingVerifiedProto(_ verified: SSKProtoVerified, tx: DBWriteTransaction) throws {
        guard let aci = Aci.parseFrom(aciString: verified.destinationAci) else {
            return owsFailDebug("Verification state sync message missing destination.")
        }
        Logger.info("Received verification state message for \(aci)")
        guard let rawIdentityKey = verified.identityKey else {
            return owsFailDebug("Verification state sync message for \(aci) with malformed identityKey")
        }
        let identityKey = try IdentityKey(bytes: rawIdentityKey)

        switch verified.state {
        case .default:
            applyVerificationStateAction(
                .clearVerification,
                aci: aci,
                identityKey: identityKey,
                overwriteOnConflict: false,
                tx: tx
            )
        case .verified:
            applyVerificationStateAction(
                .markVerified,
                aci: aci,
                identityKey: identityKey,
                overwriteOnConflict: true,
                tx: tx
            )
        case .unverified:
            return owsFailDebug("Verification state sync message for \(aci) has unverified state")
        case .none:
            return owsFailDebug("Verification state sync message for \(aci) has no state")
        }
    }

    private enum VerificationStateAction {
        case markVerified
        case clearVerification
    }

    private func applyVerificationStateAction(
        _ verificationStateAction: VerificationStateAction,
        aci: Aci,
        identityKey: IdentityKey,
        overwriteOnConflict: Bool,
        tx: DBWriteTransaction
    ) {
        let recipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        let recipientUniqueId = recipient.uniqueId
        var recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientUniqueId, transaction: tx)

        let shouldSaveIdentityKey: Bool
        let shouldInsertChangeMessages: Bool

        if let recipientIdentity {
            let didChangeIdentityKey = recipientIdentity.identityKey != identityKey.publicKey.keyBytes
            if didChangeIdentityKey, !overwriteOnConflict {
                // The conflict case where we receive a verification sync message whose
                // identity key disagrees with the local identity key for this recipient.
                Logger.warn("Non-matching identityKey for \(aci)")
                return
            }
            shouldSaveIdentityKey = didChangeIdentityKey
            shouldInsertChangeMessages = true
        } else if verificationStateAction == .clearVerification {
            // There's no point in creating a new recipient identity just to set its
            // verification state to default.
            return
        } else {
            shouldSaveIdentityKey = true
            shouldInsertChangeMessages = false
        }

        if shouldSaveIdentityKey {
            // Ensure a remote identity exists for this key. We may be learning about
            // it for the first time.
            saveIdentityKey(identityKey, for: aci, tx: tx)
            recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientUniqueId, transaction: tx)
        }

        guard let recipientIdentity else {
            return owsFailDebug("Missing expected identity for \(aci)")
        }
        guard recipientIdentity.identityKey == identityKey.publicKey.keyBytes else {
            return owsFailDebug("Unexpected identityKey for \(aci)")
        }

        let oldVerificationState: VerificationState = VerificationState(recipientIdentity.verificationState)
        let newVerificationState: VerificationState

        switch verificationStateAction {
        case .markVerified:
            switch oldVerificationState {
            case .verified:
                return
            case .noLongerVerified, .implicit(isAcknowledged: _):
                newVerificationState = .verified
            }
        case .clearVerification:
            switch oldVerificationState {
            case .implicit:
                return  // We can keep any implicit state.
            case .verified, .noLongerVerified:
                newVerificationState = .implicit(isAcknowledged: false)
            }
        }

        Logger.info("for \(aci): \(oldVerificationState) -> \(newVerificationState)")
        recipientIdentity.verificationState = newVerificationState.rawValue
        recipientIdentity.anyOverwritingUpdate(transaction: tx)

        if shouldInsertChangeMessages {
            saveChangeMessages(for: recipient, verificationState: newVerificationState, isLocalChange: false, tx: tx)
        }
    }

    private func saveChangeMessages(
        for signalRecipient: SignalRecipient,
        verificationState: VerificationState,
        isLocalChange: Bool,
        tx: DBWriteTransaction
    ) {
        let address = signalRecipient.address

        var relevantThreads = [TSThread]()
        relevantThreads.append(TSContactThread.getOrCreateThread(withContactAddress: address, transaction: tx))
        relevantThreads.append(contentsOf: TSGroupThread.groupThreads(with: address, transaction: tx))

        for thread in relevantThreads {
            OWSVerificationStateChangeMessage(
                thread: thread,
                timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
                recipientAddress: address,
                verificationState: verificationState.rawValue,
                isLocalChange: isLocalChange
            ).anyInsert(transaction: tx)
        }
    }

    // MARK: - Phone Number Sharing

    public func shouldSharePhoneNumber(with recipient: ServiceId, tx: DBReadTransaction) -> Bool {
        guard let recipient = recipient as? Aci else {
            return false
        }
        let aciString = recipient.serviceIdUppercaseString
        return shareMyPhoneNumberStore.getBool(aciString, defaultValue: false, transaction: tx)
    }

    public func setShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction) {
        let aciString = recipient.serviceIdUppercaseString
        shareMyPhoneNumberStore.setBool(true, key: aciString, transaction: tx)
    }

    public func clearShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction) {
        let aciString = recipient.serviceIdUppercaseString
        shareMyPhoneNumberStore.removeValue(forKey: aciString, transaction: tx)
    }

    public func clearShouldSharePhoneNumberForEveryone(tx: DBWriteTransaction) {
        shareMyPhoneNumberStore.removeAll(transaction: tx)
    }

    // MARK: - Batch Identity Lookup

    public func batchUpdateIdentityKeys(for serviceIds: [ServiceId]) async throws {
        let serviceIds = Array(Set(serviceIds))
        var remainingServiceIds = serviceIds[...]

        while !remainingServiceIds.isEmpty {
            let batchServiceIds = remainingServiceIds.prefix(OWSRequestFactory.batchIdentityCheckElementsLimit)
            remainingServiceIds = remainingServiceIds.dropFirst(OWSRequestFactory.batchIdentityCheckElementsLimit)

            Logger.info("Performing batch identity key lookup for \(batchServiceIds.count) recipients. \(remainingServiceIds.count) remaining.")

            let elements = self.db.read { tx in
                batchServiceIds.compactMap { serviceId -> [String: String]? in
                    guard let identityKey = try? self.identityKey(for: serviceId, tx: tx) else { return nil }

                    let externalIdentityKey = identityKey.serialize()
                    let identityKeyDigest = Data(SHA256.hash(data: externalIdentityKey))

                    return ["uuid": serviceId.serviceIdString, "fingerprint": Data(identityKeyDigest.prefix(4)).base64EncodedString()]
                }
            }

            let request = OWSRequestFactory.batchIdentityCheckRequest(elements: elements)

            let response = try await self.networkManager.asyncRequest(request)

            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Unexpected response from batch identity request \(response.responseStatusCode)")
            }

            guard let json = response.responseBodyJson, let responseDictionary = json as? [String: AnyObject] else {
                throw OWSAssertionError("Missing or invalid JSON")
            }

            guard let responseElements = responseDictionary["elements"] as? [[String: String]], !responseElements.isEmpty else {
                continue // No safety number changes
            }

            Logger.info("Detected \(responseElements.count) identity key changes via batch request")

            await self.db.awaitableWrite { tx in
                for element in responseElements {
                    guard
                        let serviceIdString = element["uuid"],
                        let serviceId = try? ServiceId.parseFrom(serviceIdString: serviceIdString)
                    else {
                        owsFailDebug("Invalid uuid in batch identity response")
                        continue
                    }

                    guard
                        let encodedIdentityKey = element["identityKey"],
                        let externalIdentityKey = Data(base64Encoded: encodedIdentityKey),
                        let identityKey = try? IdentityKey(bytes: externalIdentityKey)
                    else {
                        owsFailDebug("Missing or invalid identity key in batch identity response")
                        continue
                    }

                    self.saveIdentityKey(identityKey, for: serviceId, tx: tx)
                }
            }
        }
    }
}

// MARK: - ObjC Bridge

class OWSIdentityManagerObjCBridge: NSObject {
    @objc
    static let identityKeyLength = UInt(OWSIdentityManagerImpl.Constants.identityKeyLength)

    @objc
    static func identityKey(forAddress address: SignalServiceAddress) -> Data? {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            let identityManager = DependenciesBridge.shared.identityManager
            return identityManager.identityKey(for: address, tx: tx)
        }
    }

    @objc
    static func saveIdentityKey(_ identityKey: Data, forServiceId serviceId: ServiceIdObjC, transaction tx: DBWriteTransaction) {
        DependenciesBridge.shared.identityManager.saveIdentityKey(identityKey, for: serviceId.wrappedValue, tx: tx)
    }
}

// MARK: - Unit Tests

#if TESTABLE_BUILD

extension OWSIdentityManager {
    @discardableResult
    func generateAndPersistNewIdentityKey(for identity: OWSIdentity) -> ECKeyPair {
        let result = generateNewIdentityKeyPair()
        DependenciesBridge.shared.db.write { tx in
            setIdentityKeyPair(result, for: identity, tx: tx)
        }
        return result
    }
}

#endif
