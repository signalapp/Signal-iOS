//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import LibSignalClient

extension Notification.Name {
    public static let syncManagerConfigurationSyncDidComplete = Notification.Name("OWSSyncManagerConfigurationSyncDidCompleteNotification")
    public static let syncManagerKeysSyncDidComplete = Notification.Name("OWSSyncManagerKeysSyncDidCompleteNotification")
}

public class OWSSyncManager {
    private static var keyValueStore: KeyValueStore {
        KeyValueStore(collection: "kTSStorageManagerOWSSyncManagerCollection")
    }

    private let contactSyncQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    private let appReadiness: AppReadiness

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        SwiftSingletons.register(self)
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            self.addObservers()

            if TSAccountManagerObjcBridge.isRegisteredWithMaybeTransaction {
                if TSAccountManagerObjcBridge.isPrimaryDeviceWithMaybeTransaction {
                    // syncAllContactsIfNecessary will skip if nothing has changed,
                    // so this won't yield redundant traffic.
                    Task {
                        try await self.syncAllContactsIfNecessary()
                    }
                } else {
                    self.sendAllSyncRequestMessagesIfNecessary().catch { (_ error: Error) in
                        Logger.error("Error: \(error).")
                    }
                }
            }
        }
    }

    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(signalAccountsDidChange(_:)), name: .OWSContactsManagerSignalAccountsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(registrationStateDidChange(_:)), name: RegistrationStateChangeNotifications.registrationStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(_:)), name: .OWSApplicationWillEnterForeground, object: nil)
    }

    // MARK: - Notifications

    @objc
    private func signalAccountsDidChange(_ notification: AnyObject) {
        AssertIsOnMainThread()
        Task {
            try await self.syncAllContactsIfNecessary()
        }
    }

    @objc
    private func registrationStateDidChange(_ notification: AnyObject) {
        AssertIsOnMainThread()
        Task {
            try await self.syncAllContactsIfNecessary()
        }
    }

    @objc
    private func willEnterForeground(_ notification: AnyObject) {
        AssertIsOnMainThread()
        Task {
            try await self.syncAllContactsIfFullSyncRequested()
        }
    }
}

extension OWSSyncManager: SyncManagerProtocolObjc {

    // MARK: - Configuration Sync

    private func _sendConfigurationSyncMessage(tx: DBWriteTransaction) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let registeredState = try? tsAccountManager.registeredState(tx: tx) else {
            return
        }

        let thread = TSContactThread.getOrCreateThread(withContactAddress: registeredState.localIdentifiers.aciAddress, transaction: tx)
        let linkPreviews = DependenciesBridge.shared.linkPreviewSettingStore.areLinkPreviewsEnabled(tx: tx)
        let readReceipts = OWSReceiptManager.areReadReceiptsEnabled(transaction: tx)
        let sealedSenderIndicators = SSKEnvironment.shared.preferencesRef.shouldShowUnidentifiedDeliveryIndicators(transaction: tx)
        let typingIndicators = SSKEnvironment.shared.typingIndicatorsRef.areTypingIndicatorsEnabled()

        let configurationSyncMessage = OWSSyncConfigurationMessage(
            localThread: thread,
            readReceiptsEnabled: readReceipts,
            showUnidentifiedDeliveryIndicators: sealedSenderIndicators,
            showTypingIndicators: typingIndicators,
            sendLinkPreviews: linkPreviews,
            provisioningVersion: LinkingProvisioningMessage.Constants.provisioningVersion,
            transaction: tx,
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: configurationSyncMessage,
        )

        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
    }

    public func sendConfigurationSyncMessage() {
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task { await SSKEnvironment.shared.databaseStorageRef.awaitableWrite(block: self._sendConfigurationSyncMessage(tx:)) }
        }
    }
}

extension OWSSyncManager: SyncManagerProtocol, SyncManagerProtocolSwift {

    // MARK: - Constants

    private enum Constants {
        static let lastContactSyncKey = "kTSStorageManagerOWSSyncManagerLastMessageKey"
        static let fullSyncRequestIdKey = "FullSyncRequestId"
        static let syncRequestedAppVersionKey = "SyncRequestedAppVersion"
    }

    // MARK: - Sync Requests

    public func sendAllSyncRequestMessagesIfNecessary() -> Promise<Void> {
        return Promise.wrapAsync { try await self._sendAllSyncRequestMessages(onlyIfNecessary: true) }
    }

    public func sendAllSyncRequestMessages(timeout: TimeInterval) -> Promise<Void> {
        return Promise.wrapAsync { try await self._sendAllSyncRequestMessages(onlyIfNecessary: false) }.timeout(seconds: timeout, substituteValue: ())
    }

    private func _sendAllSyncRequestMessages(onlyIfNecessary: Bool) async throws {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        _ = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let completionGuarantees = await databaseStorage.awaitableWrite { transaction -> [Guarantee<Notification>] in
            let currentAppVersion = AppVersionImpl.shared.currentAppVersion
            let syncRequestedAppVersion = {
                Self.keyValueStore.getString(
                    Constants.syncRequestedAppVersionKey,
                    transaction: transaction,
                )
            }

            // If we don't need to send sync messages, don't send them.
            if onlyIfNecessary, currentAppVersion == syncRequestedAppVersion() {
                return []
            }

            // Otherwise, send them & mark that we sent them for this app version.
            self.sendSyncRequestMessage(.blocked, transaction: transaction)
            self.sendSyncRequestMessage(.configuration, transaction: transaction)
            self.sendSyncRequestMessage(.contacts, transaction: transaction)
            self.sendSyncRequestMessage(.keys, transaction: transaction)

            Self.keyValueStore.setString(
                currentAppVersion,
                key: Constants.syncRequestedAppVersionKey,
                transaction: transaction,
            )

            return [
                NotificationCenter.default.observe(once: .incomingContactSyncDidComplete),
                NotificationCenter.default.observe(once: .syncManagerConfigurationSyncDidComplete),
                NotificationCenter.default.observe(once: BlockingManager.blockedSyncDidComplete),
                NotificationCenter.default.observe(once: .syncManagerKeysSyncDidComplete),
            ]
        }
        for completionGuarantee in completionGuarantees {
            _ = await completionGuarantee.awaitable()
        }
    }

    public func sendKeysSyncMessage() {
        Logger.info("")

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let registeredState = try? tsAccountManager.registeredStateWithMaybeSneakyTransaction() else {
            owsFailDebug("Unexpectedly tried to send sync request before registration.")
            return
        }

        guard registeredState.isPrimary else {
            owsFailDebug("Keys sync should only be initiated from the primary device")
            return
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            self.sendKeysSyncMessage(tx: transaction)
        }
    }

    public func sendKeysSyncMessage(tx: DBWriteTransaction) {
        Logger.info("")

        guard DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice else {
            return owsFailDebug("Keys sync should only be initiated from the registered primary device")
        }

        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: tx) else {
            return owsFailDebug("Missing thread")
        }

        let accountEntropyPool = DependenciesBridge.shared.accountKeyStore.getAccountEntropyPool(tx: tx)
        if accountEntropyPool == nil {
            Logger.warn("Expecting AEP present for sync message")
        }

        let masterKey = DependenciesBridge.shared.accountKeyStore.getMasterKey(tx: tx)

        guard accountEntropyPool != nil || masterKey != nil else {
            return owsFailDebug("Missing root key")
        }

        let mrbk = DependenciesBridge.shared.accountKeyStore.getOrGenerateMediaRootBackupKey(tx: tx)

        let syncKeysMessage = OWSSyncKeysMessage(
            localThread: thread,
            accountEntropyPool: accountEntropyPool?.rawString,
            masterKey: masterKey?.rawData,
            mediaRootBackupKey: mrbk.serialize(),
            transaction: tx,
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: syncKeysMessage,
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
    }

    public func processIncomingKeysSyncMessage(_ syncMessage: SSKProtoSyncMessageKeys, transaction: DBWriteTransaction) {
        guard !DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction).isRegisteredPrimaryDevice else {
            return owsFailDebug("Key sync messages should only be processed on linked devices")
        }

        do {
            try DependenciesBridge.shared.svr.storeKeys(
                fromKeysSyncMessage: syncMessage,
                authedDevice: .implicit,
                tx: transaction,
            )
        } catch {
            switch error {
            case .missingMasterKey:
                Logger.warn("Key sync messages missing master key")
            case .missingOrInvalidMRBK:
                Logger.warn("Key sync messages missing or invalid media root backup key")
            }
        }

        transaction.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .syncManagerKeysSyncDidComplete, object: nil)
        }
    }

    public func sendKeysSyncRequestMessage(transaction: DBWriteTransaction) {
        sendSyncRequestMessage(.keys, transaction: transaction)
    }

    public func processIncomingFetchLatestSyncMessage(
        _ syncMessage: SSKProtoSyncMessageFetchLatest,
        transaction: DBWriteTransaction,
    ) {
        switch syncMessage.unwrappedType {
        case .unknown:
            owsFailDebug("Unknown fetch latest type")
        case .localProfile:
            let pendingTask = MessageReceiver.buildPendingTask()
            Task {
                defer { pendingTask.complete() }
                _ = try await SSKEnvironment.shared.profileManagerRef.fetchLocalUsersProfile(authedAccount: .implicit())
            }
        case .storageManifest:
            SSKEnvironment.shared.storageServiceManagerRef.restoreOrCreateManifestIfNecessary(
                authedDevice: .implicit,
                masterKeySource: .implicit,
            )
        case .subscriptionStatus:
            Logger.warn("Ignoring subscription status update fetch-latest sync message.")
        }
    }

    public func processIncomingMessageRequestResponseSyncMessage(
        _ syncMessage: SSKProtoSyncMessageMessageRequestResponse,
        transaction: DBWriteTransaction,
    ) {
        guard
            let thread = { () -> TSThread? in
                if let groupId = syncMessage.groupID {
                    return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
                }
                if
                    let threadAci = Aci.parseFrom(
                        serviceIdBinary: syncMessage.threadAciBinary,
                        serviceIdString: syncMessage.threadAci,
                    )
                {
                    return TSContactThread.getWithContactAddress(SignalServiceAddress(threadAci), transaction: transaction)
                }
                return nil
            }()
        else {
            return owsFailDebug("message request response couldn't find thread")
        }

        let blockingManager = SSKEnvironment.shared.blockingManagerRef
        let hidingManager = DependenciesBridge.shared.recipientHidingManager
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher

        switch syncMessage.type {
        case .accept:
            blockingManager.removeBlockedThread(thread, wasLocallyInitiated: false, transaction: transaction)
            switch thread {
            case let thread as TSGroupThread:
                // TODO: Fix userProfileWriter.
                profileManager.addGroupId(
                    toProfileWhitelist: thread.groupModel.groupId,
                    userProfileWriter: .localUser,
                    transaction: transaction,
                )

            case let thread as TSContactThread:
                /// When we accept a message request on a linked device, we unhide the
                /// message sender. We will eventually also learn about the unhide via a
                /// StorageService contact sync, since the linked device should mark
                /// unhidden in StorageService. But it doesn't hurt to get ahead of the game
                /// and unhide here.
                if var recipient = recipientFetcher.fetchOrCreate(address: thread.contactAddress, tx: transaction) {
                    hidingManager.removeHiddenRecipient(&recipient, wasLocallyInitiated: false, tx: transaction)
                    // TODO: Fix userProfileWriter.
                    profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .localUser, tx: transaction)
                }

            default:
                owsFailDebug("can't accept messages request for \(type(of: thread))")
            }
        case .delete:
            DependenciesBridge.shared.threadSoftDeleteManager.softDelete(
                threads: [thread],
                sendDeleteForMeSyncMessage: false,
                tx: transaction,
            )
        case .block:
            SSKEnvironment.shared.blockingManagerRef.addBlockedThread(thread, blockMode: .remote, transaction: transaction)
        case .blockAndDelete:
            DependenciesBridge.shared.threadSoftDeleteManager.softDelete(
                threads: [thread],
                sendDeleteForMeSyncMessage: false,
                tx: transaction,
            )
            SSKEnvironment.shared.blockingManagerRef.addBlockedThread(thread, blockMode: .remote, transaction: transaction)
        case .spam:
            TSInfoMessage(thread: thread, messageType: .reportedSpam).anyInsert(transaction: transaction)
        case .blockAndSpam:
            SSKEnvironment.shared.blockingManagerRef.addBlockedThread(thread, blockMode: .remote, transaction: transaction)
            TSInfoMessage(thread: thread, messageType: .reportedSpam).anyInsert(transaction: transaction)
        case .unknown, .none:
            owsFailDebug("unexpected message request response type")
        }
    }

    public func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType) {
        Logger.info("")

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            owsFailDebug("Unexpectedly tried to send sync message before registration.")
            return
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            self.sendMessageRequestResponseSyncMessage(thread: thread, responseType: responseType, transaction: transaction)
        }
    }

    public func sendMessageRequestResponseSyncMessage(
        thread: TSThread,
        responseType: OWSSyncMessageRequestResponseType,
        transaction: DBWriteTransaction,
    ) {
        Logger.info("")

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let registeredState = try? tsAccountManager.registeredState(tx: transaction) else {
            owsFailDebug("Unexpectedly tried to send sync message before registration.")
            return
        }

        let localThread = TSContactThread.getOrCreateThread(
            withContactAddress: registeredState.localIdentifiers.aciAddress,
            transaction: transaction,
        )

        let syncMessageRequestResponse = OWSSyncMessageRequestResponseMessage(
            localThread: localThread,
            messageRequestThread: thread,
            responseType: responseType,
            transaction: transaction,
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: syncMessageRequestResponse,
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
    }

    // MARK: - Contact Sync

    public func syncAllContacts() async throws {
        owsAssertDebug(canSendContactSyncMessage())
        try await syncContacts(mode: .allSignalAccounts)
    }

    fileprivate func syncAllContactsIfNecessary() async throws {
        owsAssertDebug(CurrentAppContext().isMainApp)
        try await syncContacts(mode: .allSignalAccountsIfChanged)
    }

    public func syncAllContactsIfFullSyncRequested() async throws {
        owsAssertDebug(CurrentAppContext().isMainApp)
        try await syncContacts(mode: .allSignalAccountsIfFullSyncRequested)
    }

    private enum ContactSyncMode {
        case allSignalAccounts
        case allSignalAccountsIfChanged
        case allSignalAccountsIfFullSyncRequested
    }

    private func canSendContactSyncMessage() -> Bool {
        guard appReadiness.isAppReady else {
            return false
        }
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice else {
            return false
        }
        return true
    }

    private func syncContacts(mode: ContactSyncMode) async throws {
        guard canSendContactSyncMessage() else {
            throw OWSGenericError("Not ready to sync contacts.")
        }

        try await contactSyncQueue.run {
            try await self._syncContacts(mode: mode)
        }
    }

    private func _syncContacts(mode: ContactSyncMode) async throws {
        let logger = PrefixedLogger(prefix: "ContactSync:\(mode)")

        // Don't bother sending sync messages with the same data as the last
        // successfully sent contact sync message.
        let opportunistic = mode == .allSignalAccountsIfChanged

        if CurrentAppContext().isNSE {
            logger.warn("Skipping: in NSE.")

            // If a full sync is specifically requested in the NSE, mark it so that the
            // main app can send that request the next time in runs.
            if mode == .allSignalAccounts {
                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                    Self.keyValueStore.setString(UUID().uuidString, key: Constants.fullSyncRequestIdKey, transaction: tx)
                }
            }
            return
        }

        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let (localIdentifiers, hasAnyLinkedDevice) = try SSKEnvironment.shared.databaseStorageRef.read { tx in
            let registeredState = try tsAccountManager.registeredState(tx: tx)
            let localIdentifiers = registeredState.localIdentifiers
            let localRecipient = recipientDatabaseTable.fetchRecipient(serviceId: localIdentifiers.aci, transaction: tx)
            return (localIdentifiers, (localRecipient?.deviceIds ?? []).count >= 2)
        }

        // Don't bother building the message if nobody will receive it. If a new
        // device is linked, they will request a re-send.
        guard hasAnyLinkedDevice else {
            logger.warn("Skipping: no linked devices.")
            return
        }

        let thread = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            return TSContactThread.getOrCreateThread(withContactAddress: localIdentifiers.aciAddress, transaction: tx)
        }

        let result = try SSKEnvironment.shared.databaseStorageRef.read { tx in try buildContactSyncMessage(in: thread, mode: mode, tx: tx) }
        guard let result else {
            logger.warn("Skipping: no buildContactSyncMessageResult.")
            return
        }

        let messageHash: Data
        do {
            messageHash = try Cryptography.computeSHA256DigestOfFile(at: result.syncFileUrl)
        } catch {
            owsFailDebug("Error: \(error).")
            throw OWSError(error: .contactSyncFailed, description: "Could not sync contacts.", isRetryable: false)
        }

        // If the NSE requested a sync and the main app does an opportunistic sync,
        // we should send that request since we've been given a strong signal that
        // someone is waiting to receive this message.
        if opportunistic, result.fullSyncRequestId == nil, messageHash == result.previousMessageHash {
            // Ignore redundant contacts sync message.
            logger.warn("Skipping: redundant.")
            return
        }

        let dataSource = DataSourcePath(fileUrl: result.syncFileUrl, ownership: .owned)

        let uploadResult = try await DependenciesBridge.shared.attachmentUploadManager.uploadTransientAttachment(dataSource: dataSource)
        let message = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return OWSSyncContactsMessage(uploadedAttachment: uploadResult, localThread: thread, tx: tx)
        }

        let preparedMessage = PreparedOutgoingMessage.preprepared(contactSyncMessage: message)
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            return SSKEnvironment.shared.messageSenderJobQueueRef.add(
                .promise,
                message: preparedMessage,
                limitToCurrentProcessLifetime: true,
                transaction: tx,
            )
        }.awaitable()

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            Self.keyValueStore.setData(messageHash, key: Constants.lastContactSyncKey, transaction: tx)
            self.clearFullSyncRequestId(ifMatches: result.fullSyncRequestId, tx: tx)
        }

        logger.info("Sent!")
    }

    private struct BuildContactSyncMessageResult {
        var syncFileUrl: URL
        var fullSyncRequestId: String?
        var previousMessageHash: Data?
    }

    private func buildContactSyncMessage(
        in thread: TSThread,
        mode: ContactSyncMode,
        tx: DBReadTransaction,
    ) throws -> BuildContactSyncMessageResult? {
        // Check if there's a pending request from the NSE. Any full sync in the
        // main app can clear this flag, even if it's not started in response to
        // calling syncAllContactsIfFullSyncRequested.
        let fullSyncRequestId = Self.keyValueStore.getString(Constants.fullSyncRequestIdKey, transaction: tx)

        // However, only syncAllContactsIfFullSyncRequested-initiated requests
        // should be skipped if there's no request.
        if mode == .allSignalAccountsIfFullSyncRequested, fullSyncRequestId == nil {
            return nil
        }

        guard
            let syncFileUrl = ContactSyncAttachmentBuilder.buildAttachmentFile(
                contactsManager: SSKEnvironment.shared.contactManagerImplRef,
                tx: tx,
            )
        else {
            owsFailDebug("Failed to serialize contacts sync message.")
            throw OWSError(error: .contactSyncFailed, description: "Could not sync contacts.", isRetryable: false)
        }
        return BuildContactSyncMessageResult(
            syncFileUrl: syncFileUrl,
            fullSyncRequestId: fullSyncRequestId,
            previousMessageHash: Self.keyValueStore.getData(Constants.lastContactSyncKey, transaction: tx),
        )
    }

    private func clearFullSyncRequestId(ifMatches requestId: String?, tx: DBWriteTransaction) {
        guard let requestId else {
            return
        }
        let storedRequestId = Self.keyValueStore.getString(Constants.fullSyncRequestIdKey, transaction: tx)
        // If the requestId we just finished matches the one in the database, we've
        // fulfilled the contract with the NSE. If the NSE triggers *another* sync
        // while this is outstanding, the match will fail, and we'll kick off
        // another sync at the next opportunity.
        if storedRequestId == requestId {
            Self.keyValueStore.removeValue(forKey: Constants.fullSyncRequestIdKey, transaction: tx)
        }
    }

    // MARK: - Fetch Latest

    public func sendFetchLatestProfileSyncMessage(tx: DBWriteTransaction) {
        _sendFetchLatestSyncMessage(type: .localProfile, tx: tx)
    }

    public func sendFetchLatestStorageManifestSyncMessage() async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in self._sendFetchLatestSyncMessage(type: .storageManifest, tx: tx) }
    }

    public func sendFetchLatestSubscriptionStatusSyncMessage() { sendFetchLatestSyncMessage(type: .subscriptionStatus) }

    private func sendFetchLatestSyncMessage(type: OWSSyncFetchType) {
        Task { await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in self._sendFetchLatestSyncMessage(type: type, tx: tx) } }
    }

    private func _sendFetchLatestSyncMessage(type: OWSSyncFetchType, tx: DBWriteTransaction) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let registeredState = try? tsAccountManager.registeredState(tx: tx) else {
            owsFailDebug("Tried to send sync message before registration.")
            return
        }

        let thread = TSContactThread.getOrCreateThread(
            withContactAddress: registeredState.localIdentifiers.aciAddress,
            transaction: tx,
        )

        let fetchLatestSyncMessage = OWSSyncFetchLatestMessage(localThread: thread, fetchType: type, transaction: tx)
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: fetchLatestSyncMessage,
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
    }

    public func processIncomingConfigurationSyncMessage(_ syncMessage: SSKProtoSyncMessageConfiguration, transaction: DBWriteTransaction) {
        if syncMessage.hasReadReceipts {
            SSKEnvironment.shared.receiptManagerRef.setAreReadReceiptsEnabled(syncMessage.readReceipts, transaction: transaction)
        }
        if syncMessage.hasUnidentifiedDeliveryIndicators {
            let updatedValue = syncMessage.unidentifiedDeliveryIndicators
            SSKEnvironment.shared.preferencesRef.setShouldShowUnidentifiedDeliveryIndicators(updatedValue, transaction: transaction)
        }
        if syncMessage.hasTypingIndicators {
            SSKEnvironment.shared.typingIndicatorsRef.setTypingIndicatorsEnabled(value: syncMessage.typingIndicators, transaction: transaction)
        }
        if syncMessage.hasLinkPreviews {
            let linkPreviewSettingStore = DependenciesBridge.shared.linkPreviewSettingStore
            linkPreviewSettingStore.setAreLinkPreviewsEnabled(syncMessage.linkPreviews, tx: transaction)
        }
        transaction.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .syncManagerConfigurationSyncDidComplete, object: nil)
        }
    }

    public func processIncomingContactsSyncMessage(_ syncMessage: SSKProtoSyncMessageContacts, transaction: DBWriteTransaction) {
        guard
            syncMessage.blob.hasCdnNumber,
            let cdnKey = syncMessage.blob.cdnKey?.nilIfEmpty,
            let encryptionKey = syncMessage.blob.key?.nilIfEmpty,
            let digest = syncMessage.blob.digest?.nilIfEmpty,
            syncMessage.blob.hasSize
        else {
            owsFailDebug("failed to create attachment download info from incoming contacts sync message")
            return
        }
        SSKEnvironment.shared.smJobQueuesRef.incomingContactSyncJobQueue.add(
            cdnNumber: syncMessage.blob.cdnNumber,
            cdnKey: cdnKey,
            encryptionKey: encryptionKey,
            digest: digest,
            plaintextLength: syncMessage.blob.size,
            isComplete: syncMessage.isComplete,
            tx: transaction,
        )
    }

    public func sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeoutSeconds: TimeInterval) -> Promise<[String]> {
        Logger.info("")
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return Promise(error: OWSAssertionError("Unexpectedly tried to send sync request before registration."))
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            self.sendSyncRequestMessage(.blocked, transaction: transaction)
            self.sendSyncRequestMessage(.configuration, transaction: transaction)
            self.sendSyncRequestMessage(.contacts, transaction: transaction)
        }

        let notificationsPromise: Promise<([(threadUniqueId: String, sortOrder: UInt32)], Void, Void)> = Promise.when(
            fulfilled:
            NotificationCenter.default.observe(once: .incomingContactSyncDidComplete).map { $0.insertedThreads }.timeout(seconds: timeoutSeconds, substituteValue: []),
            NotificationCenter.default.observe(once: .syncManagerConfigurationSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds),
            NotificationCenter.default.observe(once: BlockingManager.blockedSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds),
        )

        return notificationsPromise.map { insertedThreads, _, _ -> [String] in
            return insertedThreads.sorted(by: { $0.sortOrder < $1.sortOrder }).map({ $0.threadUniqueId })
        }
    }

    private func sendSyncRequestMessage(
        _ requestType: SSKProtoSyncMessageRequestType,
        transaction: DBWriteTransaction,
    ) {
        switch requestType {
        case .unknown:
            owsFailDebug("should not request unknown")
        case .contacts:
            Logger.info("contacts")
        case .blocked:
            Logger.info("blocked")
        case .configuration:
            Logger.info("configuration")
        case .keys:
            Logger.info("keys")
        }

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let registeredState = try? tsAccountManager.registeredStateWithMaybeSneakyTransaction() else {
            owsFailDebug("Unexpectedly tried to send sync request before registration.")
            return
        }

        guard !registeredState.isPrimary else {
            owsFailDebug("Sync request should only be sent from a linked device")
            return
        }

        let thread = TSContactThread.getOrCreateThread(
            withContactAddress: registeredState.localIdentifiers.aciAddress,
            transaction: transaction,
        )

        let syncRequestMessage = OWSSyncRequestMessage(localThread: thread, requestType: requestType.rawValue, transaction: transaction)
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: syncRequestMessage,
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
    }
}

// MARK: -

private extension Notification {
    var insertedThreads: [(threadUniqueId: String, sortOrder: UInt32)] {
        return userInfo?[IncomingContactSyncJobQueue.Constants.insertedThreads] as! [(threadUniqueId: String, sortOrder: UInt32)]
    }
}
