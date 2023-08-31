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
    func identityKey(for accountId: AccountId, tx: DBReadTransaction) -> Data?

    @discardableResult
    func saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, tx: DBWriteTransaction) -> Bool
    @discardableResult
    func saveIdentityKey(_ identityKey: Data, for accountId: AccountId, tx: DBWriteTransaction) -> Bool

    func untrustedIdentityForSending(
        to address: SignalServiceAddress,
        untrustedThreshold: TimeInterval,
        tx: DBReadTransaction
    ) -> OWSRecipientIdentity?

    func isTrustedIdentityKey(
        _ identityKey: Data,
        address: SignalServiceAddress,
        direction: TSMessageDirection,
        untrustedThreshold: TimeInterval,
        tx: DBReadTransaction
    ) -> Bool

    func tryToSyncQueuedVerificationStates()

    func verificationState(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSVerificationState
    func setVerificationState(
        _ verificationState: OWSVerificationState,
        identityKey: Data,
        address: SignalServiceAddress,
        isUserInitiatedChange: Bool,
        tx: DBWriteTransaction
    )

    func processIncomingVerifiedProto(_ verified: SSKProtoVerified, tx: DBWriteTransaction) throws
    func processIncomingPniChangePhoneNumber(
        proto: SSKProtoSyncMessagePniChangeNumber,
        updatedPni updatedPniString: String?,
        preKeyManager: PreKeyManager,
        tx: DBWriteTransaction
    )

    func shouldSharePhoneNumber(with serviceId: ServiceId, tx: DBReadTransaction) -> Bool
    func setShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction)
    func clearShouldSharePhoneNumber(with recipient: ServiceId, tx: DBWriteTransaction)
    func clearShouldSharePhoneNumberForEveryone(tx: DBWriteTransaction)

    func batchUpdateIdentityKeys(for serviceIds: [ServiceId]) -> Promise<Void>
}

public enum TSMessageDirection {
    case incoming
    case outgoing
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
        return tsAccountManager.getOrGenerateRegistrationId(transaction: context.asTransaction)
    }

    public func saveIdentity(
        _ identity: LibSignalClient.IdentityKey,
        for address: ProtocolAddress,
        context: StoreContext
    ) throws -> Bool {
        identityManager.saveIdentityKey(
            identity.serializeAsData(),
            for: address.serviceId,
            tx: context.asTransaction.asV2Write
        )
    }

    public func isTrustedIdentity(_ identity: LibSignalClient.IdentityKey,
                                  for address: ProtocolAddress,
                                  direction: Direction,
                                  context: StoreContext) throws -> Bool {
        return identityManager.isTrustedIdentityKey(
            identity.serializeAsData(),
            address: SignalServiceAddress(from: address),
            direction: TSMessageDirection(direction),
            untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
            tx: context.asTransaction.asV2Read
        )
    }

    public func identity(for address: ProtocolAddress, context: StoreContext) throws -> LibSignalClient.IdentityKey? {
        guard let data = identityManager.identityKey(for: SignalServiceAddress(from: address), tx: context.asTransaction.asV2Read) else {
            return nil
        }
        return try LibSignalClient.IdentityKey(publicKey: ECPublicKey(keyData: data).key)
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
        public static let minimumUntrustedThreshold: TimeInterval = 5
        public static let maximumUntrustedThreshold: TimeInterval = kHourInterval
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

    private func ensureAccountId(for address: SignalServiceAddress, tx: DBWriteTransaction) -> AccountId {
        return OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: SDSDB.shimOnlyBridge(tx))
    }

    private func accountId(for address: SignalServiceAddress, tx: DBReadTransaction) -> AccountId? {
        return OWSAccountIdFinder.accountId(forAddress: address, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func recipientIdentity(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSRecipientIdentity? {
        guard let accountId = accountId(for: address, tx: tx) else {
            return nil
        }
        return OWSRecipientIdentity.anyFetch(uniqueId: accountId, transaction: SDSDB.shimOnlyBridge(tx))
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
        guard let accountId = accountId(for: address, tx: tx) else { return nil }
        return identityKey(for: accountId, tx: tx)
    }

    public func identityKey(for accountId: AccountId, tx: DBReadTransaction) -> Data? {
        owsAssertDebug(!accountId.isEmpty)
        return OWSRecipientIdentity.anyFetch(uniqueId: accountId, transaction: SDSDB.shimOnlyBridge(tx))?.identityKey
    }

    @discardableResult
    public func saveIdentityKey(_ identityKey: Data, for serviceId: ServiceId, tx: DBWriteTransaction) -> Bool {
        return saveIdentityKey(identityKey, for: ensureAccountId(for: SignalServiceAddress(serviceId), tx: tx), tx: tx)
    }

    @discardableResult
    public func saveIdentityKey(_ identityKey: Data, for recipientId: AccountId, tx: DBWriteTransaction) -> Bool {
        owsAssertDebug(identityKey.count == Constants.storedIdentityKeyLength)

        let existingIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx))

        guard let existingIdentity else {
            Logger.info("Saving first-use identity for \(recipientId)")
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

        let verificationState: OWSVerificationState
        let wasIdentityVerified: Bool
        switch existingIdentity.verificationState {
        case .default:
            verificationState = .default
            wasIdentityVerified = false
        case .verified, .noLongerVerified:
            verificationState = .noLongerVerified
            wasIdentityVerified = true
        }
        Logger.info("Saving new identity for \(recipientId): \(existingIdentity.verificationState) -> \(verificationState)")
        createIdentityChangeInfoMessage(for: recipientId, wasIdentityVerified: wasIdentityVerified, tx: tx)
        OWSRecipientIdentity(
            accountId: recipientId,
            identityKey: identityKey,
            isFirstKnownKey: false,
            createdAt: Date(),
            verificationState: verificationState
        ).anyUpsert(transaction: SDSDB.shimOnlyBridge(tx))
        // PNI TODO: archive PNI sessions too
        // PNI TODO: this should end the PNI session if it was sent to our PNI.
        aciProtocolStore.sessionStore.archiveAllSessions(forAccountId: recipientId, tx: tx)
        // Cancel any pending verification state sync messages for this recipient.
        clearSyncMessage(for: recipientId, tx: tx)
        fireIdentityStateChangeNotification(after: tx)
        storageServiceManager.recordPendingUpdates(updatedAccountIds: [recipientId])
        return true
    }

    private func createIdentityChangeInfoMessage(
        for accountId: AccountId,
        wasIdentityVerified: Bool,
        tx: DBWriteTransaction
    ) {
        guard let address = OWSAccountIdFinder.address(forAccountId: accountId, transaction: SDSDB.shimOnlyBridge(tx)), address.isValid else {
            owsFailDebug("Invalid address for \(accountId)")
            return
        }
        createIdentityChangeInfoMessage(for: address, wasIdentityVerified: wasIdentityVerified, tx: tx)
    }

    private func createIdentityChangeInfoMessage(
        for address: SignalServiceAddress,
        wasIdentityVerified: Bool,
        tx: DBWriteTransaction
    ) {
        let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: SDSDB.shimOnlyBridge(tx))
        let contactThreadMessage = TSErrorMessage.nonblockingIdentityChange(
            in: contactThread,
            address: address,
            wasIdentityVerified: wasIdentityVerified
        )
        contactThreadMessage.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))

        for groupThread in TSGroupThread.groupThreads(with: address, transaction: SDSDB.shimOnlyBridge(tx)) {
            TSErrorMessage.nonblockingIdentityChange(
                in: groupThread,
                address: address,
                wasIdentityVerified: wasIdentityVerified
            ).anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
        }

        notificationsManager.notifyUser(forErrorMessage: contactThreadMessage, thread: contactThread, transaction: SDSDB.shimOnlyBridge(tx))
    }

    // MARK: - Trust

    public func untrustedIdentityForSending(
        to address: SignalServiceAddress,
        untrustedThreshold: TimeInterval,
        tx: DBReadTransaction
    ) -> OWSRecipientIdentity? {
        guard let recipientIdentity = recipientIdentity(for: address, tx: tx) else {
            // trust on first use
            return nil
        }

        let isTrusted = isTrustedIdentityKey(
            recipientIdentity.identityKey,
            address: address,
            direction: .outgoing,
            untrustedThreshold: untrustedThreshold,
            tx: tx
        )

        return isTrusted ? nil : recipientIdentity
    }

    public func isTrustedIdentityKey(
        _ identityKey: Data,
        address: SignalServiceAddress,
        direction: TSMessageDirection,
        untrustedThreshold: TimeInterval,
        tx: DBReadTransaction
    ) -> Bool {
        owsAssertDebug(identityKey.count == Constants.storedIdentityKeyLength)
        owsAssertDebug(address.isValid)

        if address.isLocalAddress {
            let localIdentityKeyPair = identityKeyPair(for: .aci, tx: tx)
            guard localIdentityKeyPair?.publicKey == identityKey else {
                owsFailDebug("Wrong identity key for local account.")
                return false
            }
            return true
        }

        switch direction {
        case .incoming:
            return true
        case .outgoing:
            guard let accountId = accountId(for: address, tx: tx) else {
                owsFailDebug("Couldn't find accountId for outgoing message.")
                return false
            }
            return isTrustedKey(
                identityKey,
                forSendingTo: OWSRecipientIdentity.anyFetch(uniqueId: accountId, transaction: SDSDB.shimOnlyBridge(tx)),
                untrustedThreshold: untrustedThreshold
            )
        }
    }

    private func isTrustedKey(
        _ identityKey: Data,
        forSendingTo recipientIdentity: OWSRecipientIdentity?,
        untrustedThreshold: TimeInterval
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
            // seconds, we'll treat it as untrusted so sends fail. We enforce a minimum
            // and maximum threshold for the new window to ensure that we never inadvertently
            // block sending indefinitely or use a window so small it would be impossible
            // for the local user to notice a key change. This is a best effort, and we'll
            // continue to allow sending to the user after the "new" window elapses without
            // any explicit action from the local user.
            let clampedUntrustedThreshold = untrustedThreshold.clamp(Constants.minimumUntrustedThreshold, Constants.maximumUntrustedThreshold)
            guard abs(recipientIdentity.createdAt.timeIntervalSinceNow) >= clampedUntrustedThreshold else {
                Logger.warn("Not trusting new identity for \(recipientIdentity.accountId)")
                return false
            }
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
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }
        guard let thread = TSAccountManager.getOrCreateLocalThreadWithSneakyTransaction() else {
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
            guard let accountId_ = self.accountId(for: address, tx: tx) else {
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

    public func verificationState(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSVerificationState {
        return recipientIdentity(for: address, tx: tx)?.verificationState ?? .default
    }

    public func setVerificationState(
        _ verificationState: OWSVerificationState,
        identityKey: Data,
        address: SignalServiceAddress,
        isUserInitiatedChange: Bool,
        tx: DBWriteTransaction
    ) {
        setVerificationState(
            verificationState,
            identityKey: identityKey,
            signalRecipient: OWSAccountIdFinder.ensureRecipient(forAddress: address, transaction: SDSDB.shimOnlyBridge(tx)),
            isUserInitiatedChange: isUserInitiatedChange,
            tx: tx
        )
    }

    public func setVerificationState(
        _ verificationState: OWSVerificationState,
        identityKey: Data,
        signalRecipient: SignalRecipient,
        isUserInitiatedChange: Bool,
        tx: DBWriteTransaction
    ) {
        owsAssertDebug(identityKey.count == Constants.storedIdentityKeyLength)
        let recipientId = signalRecipient.uniqueId

        // Ensure a remote identity exists for this key. We may be learning about
        // it for the first time.
        saveIdentityKey(identityKey, for: recipientId, tx: tx)

        let recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: recipientId, transaction: SDSDB.shimOnlyBridge(tx))
        guard let recipientIdentity else {
            owsFailDebug("Missing OWSRecipientIdentity.")
            return
        }

        if recipientIdentity.verificationState == verificationState {
            return
        }

        Logger.info("setVerificationState for \(recipientId): \(recipientIdentity.verificationState) -> \(verificationState)")

        recipientIdentity.update(with: verificationState, transaction: SDSDB.shimOnlyBridge(tx))

        if isUserInitiatedChange {
            saveChangeMessages(for: signalRecipient, verificationState: verificationState, isLocalChange: true, tx: tx)
            enqueueSyncMessage(for: recipientId, tx: tx)
        } else {
            // Cancel any pending verification state sync messages for this recipient.
            clearSyncMessage(for: recipientId, tx: tx)
        }
        // Verification state has changed, so notify storage service.
        storageServiceManager.recordPendingUpdates(updatedAccountIds: [recipientId])
        fireIdentityStateChangeNotification(after: tx)
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
            applyVerificationState(
                .default,
                aci: aci,
                identityKey: identityKey,
                overwriteOnConflict: false,
                tx: tx
            )
        case .verified:
            applyVerificationState(
                .verified,
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

    private func applyVerificationState(
        _ verificationState: OWSVerificationState,
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
        } else {
            if verificationState == .default {
                // There's no point in creating a new recipient identity just to set its
                // verification state to default.
                return
            }
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

        if recipientIdentity.verificationState == verificationState {
            return
        }

        let oldVerificationState = OWSVerificationStateToString(recipientIdentity.verificationState)
        let newVerificationState = OWSVerificationStateToString(verificationState)
        Logger.info("for \(aci): \(oldVerificationState) -> \(newVerificationState)")

        recipientIdentity.update(with: verificationState, transaction: SDSDB.shimOnlyBridge(tx))

        if shouldInsertChangeMessages {
            saveChangeMessages(for: recipient, verificationState: verificationState, isLocalChange: false, tx: tx)
        }
    }

    private func saveChangeMessages(
        for signalRecipient: SignalRecipient,
        verificationState: OWSVerificationState,
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
                verificationState: verificationState,
                isLocalChange: isLocalChange
            ).anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
        }
    }

    // MARK: - PNIs

    private struct PniChangePhoneNumberData {
        let identityKeyPair: ECKeyPair
        let signedPreKey: SignalServiceKit.SignedPreKeyRecord
        // TODO (PQXDH): 8/14/2023 - This should me made non-optional after 90 days
        let lastResortKyberPreKey: SignalServiceKit.KyberPreKeyRecord?
        let registrationId: UInt32
        let e164: E164
    }

    public func processIncomingPniChangePhoneNumber(
        proto: SSKProtoSyncMessagePniChangeNumber,
        updatedPni updatedPniString: String?,
        preKeyManager: PreKeyManager,
        tx: DBWriteTransaction
    ) {
        guard
            let updatedPniString,
            let updatedPni = UUID(uuidString: updatedPniString).map({ Pni(fromUUID: $0) })
        else {
            owsFailDebug("Missing or invalid updated PNI string while processing incoming PNI change-number sync message!")
            return
        }

        guard let localAci = tsAccountManager.localIdentifiers(transaction: SDSDB.shimOnlyBridge(tx))?.aci else {
            owsFailDebug("Missing ACI while processing incoming PNI change-number sync message!")
            return
        }

        guard let pniChangeData = deserializeIncomingPniChangePhoneNumber(proto: proto) else {
            return
        }

        // Store in the right places

        // attempt this first and return before writing any other information
        do {
            if let lastResortKey = pniChangeData.lastResortKyberPreKey {
                try pniProtocolStore.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(
                    record: lastResortKey,
                    tx: tx
                )
            }
        } catch {
            owsFailDebug("Failed to store last resort Kyber prekey")
            return
        }

        setIdentityKeyPair(
            pniChangeData.identityKeyPair,
            for: .pni,
            tx: tx
        )

        pniChangeData.signedPreKey.markAsAcceptedByService()
        pniProtocolStore.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
            signedPreKeyId: pniChangeData.signedPreKey.id,
            signedPreKeyRecord: pniChangeData.signedPreKey,
            tx: tx
        )

        tsAccountManager.setPniRegistrationId(
            newRegistrationId: pniChangeData.registrationId,
            transaction: SDSDB.shimOnlyBridge(tx)
        )

        tsAccountManager.updateLocalPhoneNumber(
            E164ObjC(pniChangeData.e164),
            aci: AciObjC(localAci),
            pni: PniObjC(updatedPni),
            transaction: SDSDB.shimOnlyBridge(tx)
        )

        // Clean up thereafter

        // We need to refresh our one-time pre-keys, and should also refresh
        // our signed pre-key so we use the one generated on the primary for as
        // little time as possible.
        preKeyManager.refreshOneTimePreKeys(forIdentity: .pni, alsoRefreshSignedPreKey: true)
    }

    private func deserializeIncomingPniChangePhoneNumber(
        proto: SSKProtoSyncMessagePniChangeNumber
    ) -> PniChangePhoneNumberData? {
        guard
            let pniIdentityKeyPairData = proto.identityKeyPair,
            let pniSignedPreKeyData = proto.signedPreKey,
            proto.hasRegistrationID, proto.registrationID > 0,
            let newE164 = E164(proto.newE164)
        else {
            owsFailDebug("Invalid PNI change number proto, missing fields!")
            return nil
        }

        do {
            let pniIdentityKeyPair = ECKeyPair(try IdentityKeyPair(bytes: pniIdentityKeyPairData))
            let pniSignedPreKey = try LibSignalClient.SignedPreKeyRecord(bytes: pniSignedPreKeyData).asSSKRecord()

            var pniLastResortKyberPreKey: KyberPreKeyRecord?
            if let pniLastResortKyberKeyData = proto.lastResortKyberPreKey {
                pniLastResortKyberPreKey = try LibSignalClient.KyberPreKeyRecord(
                    bytes: pniLastResortKyberKeyData
                ).asSSKLastResortRecord()
            }

            let pniRegistrationId = proto.registrationID

            return PniChangePhoneNumberData(
                identityKeyPair: pniIdentityKeyPair,
                signedPreKey: pniSignedPreKey,
                lastResortKyberPreKey: pniLastResortKyberPreKey,
                registrationId: pniRegistrationId,
                e164: newE164
            )
        } catch let error {
            owsFailDebug("Error while deserializing PNI change-number proto: \(error)")
            return nil
        }
    }

    // MARK: - Phone Number Sharing

    public func shouldSharePhoneNumber(with serviceId: ServiceId, tx: DBReadTransaction) -> Bool {
        let serviceIdString = serviceId.serviceIdUppercaseString
        return shareMyPhoneNumberStore.getBool(serviceIdString, defaultValue: false, transaction: tx)
    }

    public func setShouldSharePhoneNumber(with recipient: Aci, tx: DBWriteTransaction) {
        let aciString = recipient.serviceIdUppercaseString
        shareMyPhoneNumberStore.setBool(true, key: aciString, transaction: tx)
    }

    public func clearShouldSharePhoneNumber(with recipient: ServiceId, tx: DBWriteTransaction) {
        let serviceIdString = recipient.serviceIdUppercaseString
        shareMyPhoneNumberStore.removeValue(forKey: serviceIdString, transaction: tx)
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
    static func saveIdentityKey(_ identityKey: Data, forRecipientId recipientId: AccountId, transaction tx: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.identityManager.saveIdentityKey(identityKey, for: recipientId, tx: tx.asV2Write)
    }

    @objc
    static func untrustedIdentityForSending(toAddress address: SignalServiceAddress) -> OWSRecipientIdentity? {
        return databaseStorage.read { tx in
            let identityManager = DependenciesBridge.shared.identityManager
            return identityManager.untrustedIdentityForSending(
                to: address,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
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

#endif
