//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Curve25519Kit
import LibSignalClient
import SignalCoreKit

public protocol OWSIdentityManager {
    func libSignalStore(for identity: OWSIdentity, tx: DBReadTransaction) throws -> IdentityStore
    func groupContainsUnverifiedMember(_ groupUniqueID: String, tx: DBReadTransaction) -> Bool
    func recipientIdentity(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSRecipientIdentity?
    func fireIdentityStateChangeNotification(after tx: DBWriteTransaction)

    func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair?
    func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction)

    func identityKey(for address: SignalServiceAddress, tx: DBReadTransaction) -> Data?
    func identityKey(for serviceId: ServiceId, tx: DBReadTransaction) throws -> IdentityKey?

    @discardableResult
    func saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, tx: DBWriteTransaction) -> Result<Bool, RecipientIdError>

    func untrustedIdentityForSending(
        to address: SignalServiceAddress,
        untrustedThreshold: Date?,
        tx: DBReadTransaction
    ) -> OWSRecipientIdentity?

    func isTrustedIdentityKey(
        _ identityKey: Data,
        serviceId: ServiceId,
        direction: TSMessageDirection,
        tx: DBReadTransaction
    ) -> Result<Bool, RecipientIdError>

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

    func batchUpdateIdentityKeys(for serviceIds: [ServiceId]) -> Promise<Void>
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

extension LibSignalClient.IdentityKey {
    fileprivate func serializeAsData() -> Data {
        return Data(publicKey.keyBytes)
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
    private let identityManager: OWSIdentityManager
    private let identityKeyPair: IdentityKeyPair
    private let tsAccountManager: TSAccountManager

    fileprivate init(
        identityManager: OWSIdentityManager,
        identityKeyPair: IdentityKeyPair,
        tsAccountManager: TSAccountManager
    ) {
        self.identityManager = identityManager
        self.identityKeyPair = identityKeyPair
        self.tsAccountManager = tsAccountManager
    }

    public func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        return identityKeyPair
    }

    public func localRegistrationId(context: StoreContext) throws -> UInt32 {
        // PNI TODO: Return the PNI registration ID here if needed.
        return tsAccountManager.getOrGenerateAciRegistrationId(tx: context.asTransaction.asV2Write)
    }

    public func saveIdentity(
        _ identity: IdentityKey,
        for address: ProtocolAddress,
        context: StoreContext
    ) throws -> Bool {
        try identityManager.saveIdentityKey(
            identity.serializeAsData(),
            for: address.serviceId,
            tx: context.asTransaction.asV2Write
        ).get()
    }

    public func isTrustedIdentity(
        _ identity: IdentityKey,
        for address: ProtocolAddress,
        direction: Direction,
        context: StoreContext
    ) throws -> Bool {
        return try identityManager.isTrustedIdentityKey(
            identity.serializeAsData(),
            serviceId: address.serviceId,
            direction: TSMessageDirection(direction),
            tx: context.asTransaction.asV2Read
        ).get()
    }

    public func identity(for address: ProtocolAddress, context: StoreContext) throws -> LibSignalClient.IdentityKey? {
        return try identityManager.identityKey(for: address.serviceId, tx: context.asTransaction.asV2Read)
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
        Curve25519.generateKeyPair()
    }
}

public class OWSIdentityManagerImpl: OWSIdentityManager {
    private let aciProtocolStore: SignalProtocolStore
    private let db: DB
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let networkManager: NetworkManager
    private let notificationsManager: NotificationsProtocol
    private let ownIdentityKeyValueStore: KeyValueStore
    private let pniProtocolStore: SignalProtocolStore
    private let queuedVerificationStateSyncMessagesKeyValueStore: KeyValueStore
    private let recipientFetcher: RecipientFetcher
    private let recipientIdFinder: RecipientIdFinder
    private let schedulers: Schedulers
    private let shareMyPhoneNumberStore: KeyValueStore
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager

    public init(
        aciProtocolStore: SignalProtocolStore,
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        messageSenderJobQueue: MessageSenderJobQueue,
        networkManager: NetworkManager,
        notificationsManager: NotificationsProtocol,
        pniProtocolStore: SignalProtocolStore,
        recipientFetcher: RecipientFetcher,
        recipientIdFinder: RecipientIdFinder,
        schedulers: Schedulers,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager
    ) {
        self.aciProtocolStore = aciProtocolStore
        self.db = db
        self.messageSenderJobQueue = messageSenderJobQueue
        self.networkManager = networkManager
        self.notificationsManager = notificationsManager
        self.ownIdentityKeyValueStore = keyValueStoreFactory.keyValueStore(
            collection: "TSStorageManagerIdentityKeyStoreCollection"
        )
        self.pniProtocolStore = pniProtocolStore
        self.queuedVerificationStateSyncMessagesKeyValueStore = keyValueStoreFactory.keyValueStore(
            collection: "OWSIdentityManager_QueuedVerificationStateSyncMessages"
        )
        self.recipientFetcher = recipientFetcher
        self.recipientIdFinder = recipientIdFinder
        self.schedulers = schedulers
        self.shareMyPhoneNumberStore = keyValueStoreFactory.keyValueStore(
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
            tsAccountManager: tsAccountManager
        )
    }

    public func groupContainsUnverifiedMember(_ groupUniqueID: String, tx: DBReadTransaction) -> Bool {
        return OWSRecipientIdentity.groupContainsUnverifiedMember(groupUniqueID, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func fireIdentityStateChangeNotification(after tx: DBWriteTransaction) {
        tx.addAsyncCompletion(on: schedulers.main) {
            NotificationCenter.default.post(name: .identityStateDidChange, object: nil)
        }
    }

    // MARK: - Fetching

    public func recipientIdentity(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSRecipientIdentity? {
        guard let recipientIdResult = recipientIdFinder.recipientId(for: address, tx: tx) else {
            return nil
        }
        switch recipientIdResult {
        case .failure(.mustNotUsePniBecauseAciExists):
            // If we pretend as though this identity doesn't exist, we'll get an error
            // when we try to send a message, we'll retry, and then we'll correctly
            // send to the ACI.
            return nil
        case .success(let recipientId):
            return OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx))
        }
    }

    // MARK: - Local Identity

    public func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair? {
        return ownIdentityKeyValueStore.getObject(forKey: identity.persistenceKey, transaction: tx) as? ECKeyPair
    }

    public func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) {
        // Under no circumstances may we *clear* our *ACI* identity key.
        owsAssert(keyPair != nil || identity != .aci)
        ownIdentityKeyValueStore.setObject(keyPair, key: identity.persistenceKey, transaction: tx)
    }

    // MARK: - Remote Identity Keys

    public func identityKey(for address: SignalServiceAddress, tx: DBReadTransaction) -> Data? {
        switch recipientIdFinder.recipientId(for: address, tx: tx) {
        case .none, .some(.failure(.mustNotUsePniBecauseAciExists)):
            return nil
        case .some(.success(let recipientId)):
            return _identityKey(for: recipientId, tx: tx)
        }
    }

    public func identityKey(for serviceId: ServiceId, tx: DBReadTransaction) throws -> IdentityKey? {
        guard let recipientIdResult = recipientIdFinder.recipientId(for: serviceId, tx: tx) else {
            return nil
        }
        guard let keyData = try _identityKey(for: recipientIdResult.get(), tx: tx) else { return nil }
        return try IdentityKey(publicKey: ECPublicKey(keyData: keyData).key)
    }

    private func _identityKey(for recipientId: AccountId, tx: DBReadTransaction) -> Data? {
        owsAssertDebug(!recipientId.isEmpty)
        return OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx))?.identityKey
    }

    @discardableResult
    public func saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, tx: DBWriteTransaction) -> Result<Bool, RecipientIdError> {
        let recipientIdResult = recipientIdFinder.ensureRecipientId(for: serviceId, tx: tx)
        return recipientIdResult.map({ _saveIdentityKey(identityKey, for: serviceId, recipientId: $0, tx: tx) })
    }

    private func _saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, recipientId: AccountId, tx: DBWriteTransaction) -> Bool {
        owsAssertDebug(identityKey.count == Constants.storedIdentityKeyLength)

        let existingIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx))
        guard let existingIdentity else {
            Logger.info("Saving first-use identity for \(serviceId)")
            OWSRecipientIdentity(
                accountId: recipientId,
                identityKey: identityKey,
                isFirstKnownKey: true,
                createdAt: Date(),
                verificationState: .default
            ).anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
            // Cancel any pending verification state sync messages for this recipient.
            clearSyncMessage(for: recipientId, tx: tx)
            fireIdentityStateChangeNotification(after: tx)
            storageServiceManager.recordPendingUpdates(updatedAccountIds: [recipientId])
            return false
        }

        guard existingIdentity.identityKey != identityKey else {
            return false
        }

        let verificationState: VerificationState
        let wasIdentityVerified: Bool
        switch VerificationState(existingIdentity.verificationState) {
        case .implicit(isAcknowledged: _):
            verificationState = .implicit(isAcknowledged: false)
            wasIdentityVerified = false
        case .verified, .noLongerVerified:
            verificationState = .noLongerVerified
            wasIdentityVerified = true
        }
        Logger.info("Saving new identity for \(serviceId): \(existingIdentity.verificationState) -> \(verificationState)")
        createIdentityChangeInfoMessage(for: serviceId, wasIdentityVerified: wasIdentityVerified, tx: tx)
        OWSRecipientIdentity(
            accountId: recipientId,
            identityKey: identityKey,
            isFirstKnownKey: false,
            createdAt: Date(),
            verificationState: verificationState.rawValue
        ).anyUpsert(transaction: SDSDB.shimOnlyBridge(tx))
        aciProtocolStore.sessionStore.archiveAllSessions(for: serviceId, tx: tx)
        // Cancel any pending verification state sync messages for this recipient.
        clearSyncMessage(for: recipientId, tx: tx)
        fireIdentityStateChangeNotification(after: tx)
        storageServiceManager.recordPendingUpdates(updatedAccountIds: [recipientId])
        return true
    }

    private func createIdentityChangeInfoMessage(
        for serviceId: ServiceId,
        wasIdentityVerified: Bool,
        tx: DBWriteTransaction
    ) {
        let contactThread = TSContactThread.getOrCreateThread(
            withContactAddress: SignalServiceAddress(serviceId),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        let contactThreadMessage = TSErrorMessage.nonblockingIdentityChange(
            in: contactThread,
            address: SignalServiceAddress(serviceId),
            wasIdentityVerified: wasIdentityVerified
        )
        contactThreadMessage.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))

        for groupThread in TSGroupThread.groupThreads(with: SignalServiceAddress(serviceId), transaction: SDSDB.shimOnlyBridge(tx)) {
            TSErrorMessage.nonblockingIdentityChange(
                in: groupThread,
                address: SignalServiceAddress(serviceId),
                wasIdentityVerified: wasIdentityVerified
            ).anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
        }

        notificationsManager.notifyUser(forErrorMessage: contactThreadMessage, thread: contactThread, transaction: SDSDB.shimOnlyBridge(tx))
    }

    // MARK: - Trust

    public func untrustedIdentityForSending(
        to address: SignalServiceAddress,
        untrustedThreshold: Date?,
        tx: DBReadTransaction
    ) -> OWSRecipientIdentity? {
        guard let recipientIdentity = recipientIdentity(for: address, tx: tx) else {
            // trust on first use
            return nil
        }

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
        recipientIdentity: OWSRecipientIdentity,
        untrustedThreshold: Date?,
        tx: DBReadTransaction
    ) -> Bool {
        owsAssertDebug(address.isValid)
        let identityKey = recipientIdentity.identityKey
        owsAssertDebug(identityKey.count == Constants.storedIdentityKeyLength)

        if address.isLocalAddress {
            return isTrustedLocalKey(identityKey, tx: tx)
        }

        return isTrustedKey(identityKey, forSendingTo: recipientIdentity, untrustedThreshold: untrustedThreshold)
    }

    public func isTrustedIdentityKey(
        _ identityKey: Data,
        serviceId: ServiceId,
        direction: TSMessageDirection,
        tx: DBReadTransaction
    ) -> Result<Bool, RecipientIdError> {
        owsAssertDebug(identityKey.count == Constants.storedIdentityKeyLength)

        let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
        if localIdentifiers?.aci == serviceId {
            return .success(isTrustedLocalKey(identityKey, tx: tx))
        }

        switch direction {
        case .incoming:
            return .success(true)
        case .outgoing:
            guard let recipientIdResult = recipientIdFinder.recipientId(for: serviceId, tx: tx) else {
                owsFailDebug("Couldn't find recipientId for outgoing message.")
                return .success(false)
            }
            return recipientIdResult.map {
                return isTrustedKey(
                    identityKey,
                    forSendingTo: OWSRecipientIdentity.anyFetch(uniqueId: $0, transaction: SDSDB.shimOnlyBridge(tx)),
                    untrustedThreshold: nil
                )
            }
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

    private func isTrustedKey(
        _ identityKey: Data,
        forSendingTo recipientIdentity: OWSRecipientIdentity?,
        untrustedThreshold: Date?
    ) -> Bool {
        owsAssertDebug(identityKey.count == Constants.storedIdentityKeyLength)

        guard let recipientIdentity else {
            return true
        }

        owsAssertDebug(recipientIdentity.identityKey.count == Constants.storedIdentityKeyLength)

        guard recipientIdentity.identityKey == identityKey else {
            Logger.warn("Key mismatch for \(recipientIdentity.uniqueId)")
            return false
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
                Logger.warn("Not trusting new identity for \(recipientIdentity.accountId)")
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
            Logger.warn("Not trusting no-longer-verified identity for \(recipientIdentity.accountId)")
            return false
        }
    }

    // MARK: - Sync Messages

    private func enqueueSyncMessage(for recipientId: AccountId, tx: DBWriteTransaction) {
        queuedVerificationStateSyncMessagesKeyValueStore.setObject(true, key: recipientId, transaction: tx)
        schedulers.main.async { self.tryToSyncQueuedVerificationStates() }
    }

    private func clearSyncMessage(for key: String, tx: DBWriteTransaction) {
        queuedVerificationStateSyncMessagesKeyValueStore.setObject(nil, key: key, transaction: tx)
    }

    public func tryToSyncQueuedVerificationStates() {
        AssertIsOnMainThread()
        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            self.schedulers.global().async { self.syncQueuedVerificationStates() }
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
        localThread: TSThread,
        tx: DBReadTransaction
    ) -> OWSVerificationStateSyncMessage? {
        guard let value = queuedVerificationStateSyncMessagesKeyValueStore.getObject(forKey: key, transaction: tx) else {
            return nil
        }
        let recipientId: AccountId
        switch value {
        case let value as Bool:
            guard value else {
                return nil
            }
            recipientId = key
        case is SignalServiceAddress:
            recipientId = key
        case let value as String:
            // Previously, we stored phone numbers in this KV store.
            let address = SignalServiceAddress(phoneNumber: value)
            guard let accountId_ = try? recipientIdFinder.recipientId(for: address, tx: tx)?.get() else {
                return nil
            }
            recipientId = accountId_
        default:
            owsFailDebug("Invalid object: \(type(of: value))")
            return nil
        }

        if recipientId.isEmpty {
            return nil
        }

        let recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx))

        guard let recipientIdentity else {
            owsFailDebug("Couldn't load recipient identity for \(recipientId)")
            return nil
        }

        let identityKey = recipientIdentity.identityKey.prependKeyType()
        guard identityKey.count == Constants.identityKeyLength else {
            owsFailDebug("Invalid recipient identity key for \(recipientId)")
            return nil
        }

        // We don't want to sync "no longer verified" state. Other
        // clients can figure this out from the /profile/ endpoint, and
        // this can cause data loss as a user's devices overwrite each
        // other's verification.
        if recipientIdentity.verificationState == .noLongerVerified {
            owsFailDebug("Queue verification state is invalid for \(recipientId)")
            return nil
        }

        guard let recipient = SignalRecipient.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx)) else {
            return nil
        }

        return OWSVerificationStateSyncMessage(
            thread: localThread,
            verificationState: recipientIdentity.verificationState,
            identityKey: identityKey,
            verificationForRecipientAddress: recipient.address,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    private func sendVerificationStateSyncMessage(for recipientId: AccountId, message: OWSVerificationStateSyncMessage) {
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
                transaction: SDSDB.shimOnlyBridge(tx)
            )

            return messageSenderJobQueue.add(
                .promise,
                message: nullMessage.asPreparer,
                limitToCurrentProcessLifetime: true,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        }

        nullMessagePromise.done(on: schedulers.global()) {
            Logger.info("Successfully sent verification state NullMessage")
            let syncMessagePromise = self.db.write { tx in
                self.messageSenderJobQueue.add(
                    .promise,
                    message: message.asPreparer,
                    limitToCurrentProcessLifetime: true,
                    transaction: SDSDB.shimOnlyBridge(tx)
                )
            }
            syncMessagePromise.done(on: self.schedulers.global()) {
                Logger.info("Successfully sent verification state sync message")
                self.db.write { tx in self.clearSyncMessage(for: recipientId, tx: tx) }
            }.catch(on: self.schedulers.global()) { error in
                Logger.error("Failed to send verification state sync message: \(error)")
            }
        }.catch(on: schedulers.global()) { error in
            Logger.error("Failed to send verification state NullMessage: \(error)")
            if error is MessageSenderNoSuchSignalRecipientError {
                Logger.info("Removing retries for syncing verification for unregistered user: \(address)")
                self.db.write { tx in self.clearSyncMessage(for: recipientId, tx: tx) }
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

        let recipient = OWSAccountIdFinder.ensureRecipient(forAddress: address, transaction: SDSDB.shimOnlyBridge(tx))
        let recipientId = recipient.uniqueId
        let recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx))
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

        Logger.info("setVerificationState for \(recipientId): \(recipientIdentity.verificationState) -> \(verificationState)")
        recipientIdentity.update(with: verificationState.rawValue, transaction: SDSDB.shimOnlyBridge(tx))

        switch (oldVerificationState, verificationState) {
        case (.implicit, .implicit):
            // We're only changing `isAcknowledged`, and that doesn't impact Storage
            // Service, sync messages, or chat events.
            break
        default:
            if isUserInitiatedChange {
                saveChangeMessages(for: recipient, verificationState: verificationState, isLocalChange: true, tx: tx)
                enqueueSyncMessage(for: recipientId, tx: tx)
            } else {
                // Cancel any pending verification state sync messages for this recipient.
                clearSyncMessage(for: recipientId, tx: tx)
            }
            // Verification state has changed, so notify storage service.
            storageServiceManager.recordPendingUpdates(updatedAccountIds: [recipientId])
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
        guard let rawIdentityKey = verified.identityKey, rawIdentityKey.count == Constants.identityKeyLength else {
            return owsFailDebug("Verification state sync message for \(aci) with malformed identityKey")
        }
        let identityKey = try rawIdentityKey.removeKeyType()

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
        identityKey: Data,
        overwriteOnConflict: Bool,
        tx: DBWriteTransaction
    ) {
        let recipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        let recipientId = recipient.uniqueId
        var recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx))

        let shouldSaveIdentityKey: Bool
        let shouldInsertChangeMessages: Bool

        if let recipientIdentity {
            if recipientIdentity.accountId != recipientId {
                return owsFailDebug("Unexpected recipientId for \(aci)")
            }
            let didChangeIdentityKey = recipientIdentity.identityKey != identityKey
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
            recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx))
        }

        guard let recipientIdentity else {
            return owsFailDebug("Missing expected identity for \(aci)")
        }
        guard recipientIdentity.accountId == recipientId else {
            return owsFailDebug("Unexpected recipientId for \(aci)")
        }
        guard recipientIdentity.identityKey == identityKey else {
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
        recipientIdentity.update(with: newVerificationState.rawValue, transaction: SDSDB.shimOnlyBridge(tx))

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
        relevantThreads.append(TSContactThread.getOrCreateThread(withContactAddress: address, transaction: SDSDB.shimOnlyBridge(tx)))
        relevantThreads.append(contentsOf: TSGroupThread.groupThreads(with: address, transaction: SDSDB.shimOnlyBridge(tx)))

        for thread in relevantThreads {
            OWSVerificationStateChangeMessage(
                thread: thread,
                recipientAddress: address,
                verificationState: verificationState.rawValue,
                isLocalChange: isLocalChange
            ).anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
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

    public func batchUpdateIdentityKeys(for serviceIds: [ServiceId]) -> Promise<Void> {
        if serviceIds.isEmpty { return .value(()) }

        let serviceIds = Set(serviceIds)
        let batchServiceIds = serviceIds.prefix(OWSRequestFactory.batchIdentityCheckElementsLimit)
        let remainingServiceIds = Array(serviceIds.subtracting(batchServiceIds))

        return firstly(on: schedulers.global()) { () -> Promise<HTTPResponse> in
            Logger.info("Performing batch identity key lookup for \(batchServiceIds.count) addresses. \(remainingServiceIds.count) remaining.")

            let elements = self.db.read { tx in
                batchServiceIds.compactMap { serviceId -> [String: String]? in
                    guard let identityKey = self.identityKey(for: SignalServiceAddress(serviceId), tx: tx) else { return nil }

                    let externalIdentityKey = identityKey.prependKeyType()
                    guard let identityKeyDigest = Cryptography.computeSHA256Digest(externalIdentityKey) else {
                        owsFailDebug("Failed to calculate SHA-256 digest for batch identity key update")
                        return nil
                    }

                    return ["uuid": serviceId.serviceIdString, "fingerprint": Data(identityKeyDigest.prefix(4)).base64EncodedString()]
                }
            }

            let request = OWSRequestFactory.batchIdentityCheckRequest(elements: elements)

            return self.networkManager.makePromise(request: request)
        }.done(on: schedulers.global()) { response in
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Unexpected response from batch identity request \(response.responseStatusCode)")
            }

            guard let json = response.responseBodyJson, let responseDictionary = json as? [String: AnyObject] else {
                throw OWSAssertionError("Missing or invalid JSON")
            }

            guard let responseElements = responseDictionary["elements"] as? [[String: String]], !responseElements.isEmpty else {
                return // No safety number changes
            }

            Logger.info("Detected \(responseElements.count) identity key changes via batch request")

            self.db.write { tx in
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
                        externalIdentityKey.count == Constants.identityKeyLength,
                        let identityKey = try? externalIdentityKey.removeKeyType()
                    else {
                        owsFailDebug("Missing or invalid identity key in batch identity response")
                        continue
                    }

                    self.saveIdentityKey(identityKey, for: serviceId, tx: tx)
                }
            }
        }.then { () -> Promise<Void> in
            return self.batchUpdateIdentityKeys(for: remainingServiceIds)
        }.catch { error in
            owsFailDebug("Batch identity key update failed with error \(error)")
        }
    }
}

// MARK: - ObjC Bridge

class OWSIdentityManagerObjCBridge: NSObject {
    @objc
    static let identityKeyLength = UInt(OWSIdentityManagerImpl.Constants.identityKeyLength)

    @objc
    static let identityStateDidChangeNotification = NSNotification.Name.identityStateDidChange

    @objc
    static func identityKeyPair(forIdentity identity: OWSIdentity) -> ECKeyPair? {
        return databaseStorage.read { tx in
            let identityManager = DependenciesBridge.shared.identityManager
            return identityManager.identityKeyPair(for: identity, tx: tx.asV2Read)
        }
    }

    @objc
    static func identityKey(forAddress address: SignalServiceAddress) -> Data? {
        return databaseStorage.read { tx in
            let identityManager = DependenciesBridge.shared.identityManager
            return identityManager.identityKey(for: address, tx: tx.asV2Read)
        }
    }

    @objc
    static func saveIdentityKey(_ identityKey: Data, forServiceId serviceId: ServiceIdObjC, transaction tx: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.identityManager.saveIdentityKey(identityKey, for: serviceId.wrappedValue, tx: tx.asV2Write)
    }

    @objc
    static func untrustedIdentityForSending(toAddress address: SignalServiceAddress) -> OWSRecipientIdentity? {
        return databaseStorage.read { tx in
            let identityManager = DependenciesBridge.shared.identityManager
            return identityManager.untrustedIdentityForSending(
                to: address,
                untrustedThreshold: nil,
                tx: tx.asV2Read
            )
        }
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

final class MockIdentityManager: OWSIdentityManager {

    private let recipientIdFinder: RecipientIdFinder

    init(recipientIdFinder: RecipientIdFinder) {
        self.recipientIdFinder = recipientIdFinder
    }

    var identityKeys = [AccountId: IdentityKey]()
    func identityKey(for serviceId: ServiceId, tx: DBReadTransaction) throws -> IdentityKey? {
        guard let recipientId = try recipientIdFinder.recipientId(for: serviceId, tx: tx)?.get() else { return nil }
        return identityKeys[recipientId]
    }

    func libSignalStore(for identity: OWSIdentity, tx: DBReadTransaction) throws -> IdentityStore { fatalError() }
    func groupContainsUnverifiedMember(_ groupUniqueID: String, tx: DBReadTransaction) -> Bool { fatalError() }
    func recipientIdentity(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSRecipientIdentity? { fatalError() }
    func fireIdentityStateChangeNotification(after tx: DBWriteTransaction) { fatalError() }
    func identityKeyPair(for identity: OWSIdentity, tx: DBReadTransaction) -> ECKeyPair? { fatalError() }
    func setIdentityKeyPair(_ keyPair: ECKeyPair?, for identity: OWSIdentity, tx: DBWriteTransaction) { fatalError() }
    func identityKey(for address: SignalServiceAddress, tx: DBReadTransaction) -> Data? { fatalError() }
    func saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, tx: DBWriteTransaction) -> Result<Bool, RecipientIdError> { fatalError() }
    func untrustedIdentityForSending(to address: SignalServiceAddress, untrustedThreshold: Date?, tx: DBReadTransaction) -> OWSRecipientIdentity? { fatalError() }
    func isTrustedIdentityKey(_ identityKey: Data, serviceId: ServiceId, direction: TSMessageDirection, tx: DBReadTransaction) -> Result<Bool, RecipientIdError> { fatalError() }
    func tryToSyncQueuedVerificationStates() { fatalError() }
    func verificationState(for address: SignalServiceAddress, tx: DBReadTransaction) -> VerificationState { fatalError() }
    func setVerificationState(_ verificationState: VerificationState, of identityKey: Data, for address: SignalServiceAddress, isUserInitiatedChange: Bool, tx: DBWriteTransaction) -> ChangeVerificationStateResult { fatalError() }
    func processIncomingVerifiedProto(_ verified: SSKProtoVerified, tx: DBWriteTransaction) throws { fatalError() }
    func processIncomingPniChangePhoneNumber(proto: SSKProtoSyncMessagePniChangeNumber, updatedPni updatedPniString: String?, preKeyManager: PreKeyManager, tx: DBWriteTransaction) { fatalError() }
    func shouldSharePhoneNumber(with serviceId: ServiceId, tx: DBReadTransaction) -> Bool { fatalError() }
    func setShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction) { fatalError() }
    func clearShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction) { fatalError() }
    func clearShouldSharePhoneNumberForEveryone(tx: DBWriteTransaction) { fatalError() }
    func batchUpdateIdentityKeys(for serviceIds: [ServiceId]) -> Promise<Void> { fatalError() }
}

#endif
