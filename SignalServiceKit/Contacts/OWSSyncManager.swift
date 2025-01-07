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

@objc
public class OWSSyncManager: NSObject {
    private static var keyValueStore: KeyValueStore {
        KeyValueStore(collection: "kTSStorageManagerOWSSyncManagerCollection")
    }

    private let contactSyncQueue = SerialTaskQueue()

    fileprivate let appReadiness: AppReadiness

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        super.init()
        SwiftSingletons.register(self)
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            self.addObservers()

            if TSAccountManagerObjcBridge.isRegisteredWithMaybeTransaction {
                if TSAccountManagerObjcBridge.isPrimaryDeviceWithMaybeTransaction {
                    // syncAllContactsIfNecessary will skip if nothing has changed,
                    // so this won't yield redundant traffic.
                    self.syncAllContactsIfNecessary()
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
        syncAllContactsIfNecessary()
    }

    @objc
    private func registrationStateDidChange(_ notification: AnyObject) {
        AssertIsOnMainThread()
        syncAllContactsIfNecessary()
    }

    @objc
    private func willEnterForeground(_ notification: AnyObject) {
        AssertIsOnMainThread()
        _ = syncAllContactsIfFullSyncRequested()
    }
}

extension OWSSyncManager: SyncManagerProtocolObjc {

    // MARK: - Configuration Sync

    private func _sendConfigurationSyncMessage(tx: SDSAnyWriteTransaction) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationState(tx: tx.asV2Read).isRegistered else {
            return
        }

        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: tx) else {
            owsFailDebug("Missing thread.")
            return
        }

        let linkPreviews = DependenciesBridge.shared.linkPreviewSettingStore.areLinkPreviewsEnabled(tx: tx.asV2Read)
        let readReceipts = OWSReceiptManager.areReadReceiptsEnabled(transaction: tx)
        let sealedSenderIndicators = SSKEnvironment.shared.preferencesRef.shouldShowUnidentifiedDeliveryIndicators(transaction: tx)
        let typingIndicators = SSKEnvironment.shared.typingIndicatorsRef.areTypingIndicatorsEnabled()

        let configurationSyncMessage = OWSSyncConfigurationMessage(
            thread: thread,
            readReceiptsEnabled: readReceipts,
            showUnidentifiedDeliveryIndicators: sealedSenderIndicators,
            showTypingIndicators: typingIndicators,
            sendLinkPreviews: linkPreviews,
            transaction: tx
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: configurationSyncMessage
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
        _sendAllSyncRequestMessages(onlyIfNecessary: true)
    }

    public func sendAllSyncRequestMessages(timeout: TimeInterval) -> Promise<Void> {
        _sendAllSyncRequestMessages(onlyIfNecessary: false).timeout(seconds: timeout, substituteValue: ())
    }

    private func _sendAllSyncRequestMessages(onlyIfNecessary: Bool) -> Promise<Void> {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return Promise(error: OWSAssertionError("Unexpectedly tried to send sync request before registration."))
        }

        return SSKEnvironment.shared.databaseStorageRef.write(.promise) { (transaction) -> Promise<Void> in
            let currentAppVersion = AppVersionImpl.shared.currentAppVersion
            let syncRequestedAppVersion = {
                Self.keyValueStore.getString(
                    Constants.syncRequestedAppVersionKey,
                    transaction: transaction.asV2Read
                )
            }

            // If we don't need to send sync messages, don't send them.
            if onlyIfNecessary, currentAppVersion == syncRequestedAppVersion() {
                return .value(())
            }

            // Otherwise, send them & mark that we sent them for this app version.
            self.sendSyncRequestMessage(.blocked, transaction: transaction)
            self.sendSyncRequestMessage(.configuration, transaction: transaction)
            self.sendSyncRequestMessage(.contacts, transaction: transaction)
            self.sendSyncRequestMessage(.keys, transaction: transaction)

            Self.keyValueStore.setString(
                currentAppVersion,
                key: Constants.syncRequestedAppVersionKey,
                transaction: transaction.asV2Write
            )

            return Promise.when(fulfilled: [
                NotificationCenter.default.observe(once: .incomingContactSyncDidComplete).asVoid(),
                NotificationCenter.default.observe(once: .syncManagerConfigurationSyncDidComplete).asVoid(),
                NotificationCenter.default.observe(once: BlockingManager.blockedSyncDidComplete).asVoid(),
                NotificationCenter.default.observe(once: .syncManagerKeysSyncDidComplete).asVoid()
            ])
        }.then(on: DependenciesBridge.shared.schedulers.sync) { $0 }
    }

    public func sendKeysSyncMessage() {
        Logger.info("")

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return owsFailDebug("Unexpectedly tried to send sync request before registration.")
        }

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? false else {
            return owsFailDebug("Keys sync should only be initiated from the primary device")
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { [weak self] transaction in
            self?.sendKeysSyncMessage(tx: transaction)
        }
    }

    public func sendKeysSyncMessage(tx: SDSAnyWriteTransaction) {
        Logger.info("")

        guard DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Write).isRegisteredPrimaryDevice else {
            return owsFailDebug("Keys sync should only be initiated from the registered primary device")
        }

        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: tx) else {
            return owsFailDebug("Missing thread")
        }

        let storageServiceKey = DependenciesBridge.shared.svrKeyDeriver.data(for: .storageService, tx: tx.asV2Read)
        let masterKey = DependenciesBridge.shared.svr.masterKeyDataForKeysSyncMessage(tx: tx.asV2Read)
        let mrbk = DependenciesBridge.shared.mrbkStore.getOrGenerateMediaRootBackupKey(tx: tx.asV2Write)
        let syncKeysMessage = OWSSyncKeysMessage(
            thread: thread,
            storageServiceKey: storageServiceKey?.rawData,
            masterKey: masterKey,
            mediaRootBackupKey: mrbk,
            transaction: tx
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: syncKeysMessage
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
    }

    public func processIncomingKeysSyncMessage(_ syncMessage: SSKProtoSyncMessageKeys, transaction: SDSAnyWriteTransaction) {
        guard !DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isRegisteredPrimaryDevice else {
            return owsFailDebug("Key sync messages should only be processed on linked devices")
        }

        if let masterKey = syncMessage.master {
            DependenciesBridge.shared.svr.storeSyncedMasterKey(
                data: masterKey,
                authedDevice: .implicit,
                updateStorageService: true,
                transaction: transaction.asV2Write
            )
        }

        try? DependenciesBridge.shared.mrbkStore.setMediaRootBackupKey(
            fromKeysSyncMessage: syncMessage,
            tx: transaction.asV2Write
        )

        transaction.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(.syncManagerKeysSyncDidComplete, object: nil)
        }
    }

    public func sendKeysSyncRequestMessage(transaction: SDSAnyWriteTransaction) {
        sendSyncRequestMessage(.keys, transaction: transaction)
    }

    public func processIncomingFetchLatestSyncMessage(
        _ syncMessage: SSKProtoSyncMessageFetchLatest,
        transaction: SDSAnyWriteTransaction
    ) {
        switch syncMessage.unwrappedType {
        case .unknown:
            owsFailDebug("Unknown fetch latest type")
        case .localProfile:
            _ = SSKEnvironment.shared.profileManagerRef.fetchLocalUsersProfile(authedAccount: .implicit())
        case .storageManifest:
            SSKEnvironment.shared.storageServiceManagerRef.restoreOrCreateManifestIfNecessary(authedDevice: .implicit)
        case .subscriptionStatus:
            Logger.warn("Ignoring subscription status update fetch-latest sync message.")
        }
    }

    public func processIncomingMessageRequestResponseSyncMessage(
        _ syncMessage: SSKProtoSyncMessageMessageRequestResponse,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let thread: TSThread = {
            if let groupId = syncMessage.groupID {
                return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
            }
            if let threadAci = Aci.parseFrom(aciString: syncMessage.threadAci) {
                return TSContactThread.getWithContactAddress(SignalServiceAddress(threadAci), transaction: transaction)
            }
            return nil
        }() else {
            return owsFailDebug("message request response couldn't find thread")
        }

        switch syncMessage.type {
        case .accept:
            SSKEnvironment.shared.blockingManagerRef.removeBlockedThread(thread, wasLocallyInitiated: false, transaction: transaction)
            if let thread = thread as? TSContactThread {
                /// When we accept a message request on a linked device,
                /// we unhide the message sender. We will eventually also
                /// learn about the unhide via a StorageService contact sync,
                /// since the linked device should mark unhidden in
                /// StorageService. But it doesn't hurt to get ahead of the
                /// game and unhide here.
                do {
                    try DependenciesBridge.shared.recipientHidingManager.removeHiddenRecipient(
                        thread.contactAddress,
                        wasLocallyInitiated: false,
                        tx: transaction.asV2Write
                    )
                } catch {
                    owsFailDebug("Unable to unhide recipient after accept sync message")
                }
            }
            SSKEnvironment.shared.profileManagerRef.addThread(
                toProfileWhitelist: thread,
                userProfileWriter: .localUser,
                transaction: transaction
            )
        case .delete:
            DependenciesBridge.shared.threadSoftDeleteManager.softDelete(
                threads: [thread],
                sendDeleteForMeSyncMessage: false,
                tx: transaction.asV2Write
            )
        case .block:
            SSKEnvironment.shared.blockingManagerRef.addBlockedThread(thread, blockMode: .remote, transaction: transaction)
        case .blockAndDelete:
            DependenciesBridge.shared.threadSoftDeleteManager.softDelete(
                threads: [thread],
                sendDeleteForMeSyncMessage: false,
                tx: transaction.asV2Write
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

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return owsFailDebug("Unexpectedly tried to send sync message before registration.")
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { [weak self] transaction in
            self?.sendMessageRequestResponseSyncMessage(thread: thread, responseType: responseType, transaction: transaction)
        }
    }

    public func sendMessageRequestResponseSyncMessage(
        thread: TSThread,
        responseType: OWSSyncMessageRequestResponseType,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("")

        guard DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isRegistered else {
            return owsFailDebug("Unexpectedly tried to send sync message before registration.")
        }

        let syncMessageRequestResponse = OWSSyncMessageRequestResponseMessage(thread: thread, responseType: responseType, transaction: transaction)
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: syncMessageRequestResponse
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
    }

    // MARK: - Contact Sync

    public func syncAllContacts() -> Promise<Void> {
        owsAssertDebug(canSendContactSyncMessage())
        return syncContacts(mode: .allSignalAccounts)
    }

    func syncAllContactsIfNecessary() {
        owsAssertDebug(CurrentAppContext().isMainApp)
        _ = syncContacts(mode: .allSignalAccountsIfChanged)
    }

    public func syncAllContactsIfFullSyncRequested() -> Promise<Void> {
        owsAssertDebug(CurrentAppContext().isMainApp)
        return syncContacts(mode: .allSignalAccountsIfFullSyncRequested)
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

    private func syncContacts(mode: ContactSyncMode) -> Promise<Void> {
        if DebugFlags.dontSendContactOrGroupSyncMessages.get() {
            Logger.info("Skipping contact sync message.")
            return .value(())
        }

        guard canSendContactSyncMessage() else {
            return Promise(error: OWSGenericError("Not ready to sync contacts."))
        }

        let syncTask = contactSyncQueue.enqueue {
            return try await self._syncContacts(mode: mode)
        }

        return Promise.wrapAsync { try await syncTask.value }
    }

    private func _syncContacts(mode: ContactSyncMode) async throws {
        // Don't bother sending sync messages with the same data as the last
        // successfully sent contact sync message.
        let opportunistic = mode == .allSignalAccountsIfChanged

        if CurrentAppContext().isNSE {
            // If a full sync is specifically requested in the NSE, mark it so that the
            // main app can send that request the next time in runs.
            if mode == .allSignalAccounts {
                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                    Self.keyValueStore.setString(UUID().uuidString, key: Constants.fullSyncRequestIdKey, transaction: tx.asV2Write)
                }
            }
            // If a full sync sync is requested in NSE, ignore it. Opportunistic syncs
            // shouldn't be requested, but this guards against cases where they are.
            return
        }

        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let (localIdentifiers, hasAnyLinkedDevice) = try SSKEnvironment.shared.databaseStorageRef.read { tx in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                throw OWSError(error: .contactSyncFailed, description: "Not registered.", isRetryable: false)
            }
            let localRecipient = recipientDatabaseTable.fetchRecipient(serviceId: localIdentifiers.aci, transaction: tx.asV2Read)
            return (localIdentifiers, (localRecipient?.deviceIds ?? []).count >= 2)
        }

        // Don't bother building the message if nobody will receive it. If a new
        // device is linked, they will request a re-send.
        guard hasAnyLinkedDevice else {
            return
        }

        let thread = await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            return TSContactThread.getOrCreateThread(withContactAddress: localIdentifiers.aciAddress, transaction: tx)
        }

        let result = try SSKEnvironment.shared.databaseStorageRef.read { tx in try buildContactSyncMessage(in: thread, mode: mode, tx: tx) }
        guard let result else {
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
            return
        }

        let dataSource = try DataSourcePath(fileUrl: result.syncFileUrl, shouldDeleteOnDeallocation: true)

        try await SSKEnvironment.shared.messageSenderRef.sendTransientContactSyncAttachment(dataSource: dataSource, thread: thread)
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            Self.keyValueStore.setData(messageHash, key: Constants.lastContactSyncKey, transaction: tx.asV2Write)
            self.clearFullSyncRequestId(ifMatches: result.fullSyncRequestId, tx: tx)
        }
    }

    private struct BuildContactSyncMessageResult {
        var syncFileUrl: URL
        var fullSyncRequestId: String?
        var previousMessageHash: Data?
    }

    private func buildContactSyncMessage(
        in thread: TSThread,
        mode: ContactSyncMode,
        tx: SDSAnyReadTransaction
    ) throws -> BuildContactSyncMessageResult? {
        // Check if there's a pending request from the NSE. Any full sync in the
        // main app can clear this flag, even if it's not started in response to
        // calling syncAllContactsIfFullSyncRequested.
        let fullSyncRequestId = Self.keyValueStore.getString(Constants.fullSyncRequestIdKey, transaction: tx.asV2Read)

        // However, only syncAllContactsIfFullSyncRequested-initiated requests
        // should be skipped if there's no request.
        if mode == .allSignalAccountsIfFullSyncRequested, fullSyncRequestId == nil {
            return nil
        }

        guard let syncFileUrl = ContactSyncAttachmentBuilder.buildAttachmentFile(
            contactsManager: SSKEnvironment.shared.contactManagerImplRef,
            tx: tx
        ) else {
            owsFailDebug("Failed to serialize contacts sync message.")
            throw OWSError(error: .contactSyncFailed, description: "Could not sync contacts.", isRetryable: false)
        }
        return BuildContactSyncMessageResult(
            syncFileUrl: syncFileUrl,
            fullSyncRequestId: fullSyncRequestId,
            previousMessageHash: Self.keyValueStore.getData(Constants.lastContactSyncKey, transaction: tx.asV2Read)
        )
    }

    private func clearFullSyncRequestId(ifMatches requestId: String?, tx: SDSAnyWriteTransaction) {
        guard let requestId else {
            return
        }
        let storedRequestId = Self.keyValueStore.getString(Constants.fullSyncRequestIdKey, transaction: tx.asV2Read)
        // If the requestId we just finished matches the one in the database, we've
        // fulfilled the contract with the NSE. If the NSE triggers *another* sync
        // while this is outstanding, the match will fail, and we'll kick off
        // another sync at the next opportunity.
        if storedRequestId == requestId {
            Self.keyValueStore.removeValue(forKey: Constants.fullSyncRequestIdKey, transaction: tx.asV2Write)
        }
    }

    // MARK: - Fetch Latest

    public func sendFetchLatestProfileSyncMessage(tx: SDSAnyWriteTransaction) {
        _sendFetchLatestSyncMessage(type: .localProfile, tx: tx)
    }

    public func sendFetchLatestStorageManifestSyncMessage() async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in self._sendFetchLatestSyncMessage(type: .storageManifest, tx: tx) }
    }

    public func sendFetchLatestSubscriptionStatusSyncMessage() { sendFetchLatestSyncMessage(type: .subscriptionStatus) }

    private func sendFetchLatestSyncMessage(type: OWSSyncFetchType) {
        Task { await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in self._sendFetchLatestSyncMessage(type: type, tx: tx) } }
    }

    private func _sendFetchLatestSyncMessage(type: OWSSyncFetchType, tx: SDSAnyWriteTransaction) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationState(tx: tx.asV2Read).isRegistered else {
            owsFailDebug("Tried to send sync message before registration.")
            return
        }

        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: tx) else {
            owsFailDebug("Missing thread.")
            return
        }

        let fetchLatestSyncMessage = OWSSyncFetchLatestMessage(thread: thread, fetchType: type, transaction: tx)
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: fetchLatestSyncMessage
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: tx)
    }

    public func processIncomingConfigurationSyncMessage(_ syncMessage: SSKProtoSyncMessageConfiguration, transaction: SDSAnyWriteTransaction) {
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
            linkPreviewSettingStore.setAreLinkPreviewsEnabled(syncMessage.linkPreviews, tx: transaction.asV2Write)
        }
        transaction.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(.syncManagerConfigurationSyncDidComplete, object: nil)
        }
    }

    public func processIncomingContactsSyncMessage(_ syncMessage: SSKProtoSyncMessageContacts, transaction: SDSAnyWriteTransaction) {
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
            tx: transaction
        )
    }

    public func sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeoutSeconds: TimeInterval) -> Promise<[String]> {
        Logger.info("")
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return Promise(error: OWSAssertionError("Unexpectedly tried to send sync request before registration."))
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            self.sendSyncRequestMessage(.blocked, transaction: transaction)
            self.sendSyncRequestMessage(.configuration, transaction: transaction)
            self.sendSyncRequestMessage(.contacts, transaction: transaction)
        }

        let notificationsPromise: Promise<([(threadUniqueId: String, sortOrder: UInt32)], Void, Void)> = Promise.when(fulfilled:
            NotificationCenter.default.observe(once: .incomingContactSyncDidComplete).map { $0.insertedThreads }.timeout(seconds: timeoutSeconds, substituteValue: []),
            NotificationCenter.default.observe(once: .syncManagerConfigurationSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds),
            NotificationCenter.default.observe(once: BlockingManager.blockedSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds)
        )

        return notificationsPromise.map { (insertedThreads, _, _) -> [String] in
            return insertedThreads.sorted(by: { $0.sortOrder < $1.sortOrder }).map({ $0.threadUniqueId })
        }
    }

    private func sendSyncRequestMessage(
        _ requestType: SSKProtoSyncMessageRequestType,
        transaction: SDSAnyWriteTransaction
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

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return owsFailDebug("Unexpectedly tried to send sync request before registration.")
        }

        guard !DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice else {
            return owsFailDebug("Sync request should only be sent from a linked device")
        }

        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: transaction) else {
            return owsFailDebug("Missing thread")
        }

        let syncRequestMessage = OWSSyncRequestMessage(thread: thread, requestType: requestType.rawValue, transaction: transaction)
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: syncRequestMessage
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
