//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation
import LibSignalClient
import SignalServiceKit

extension OWSSyncManager: SyncManagerProtocol, SyncManagerProtocolSwift {

    // MARK: - Constants

    private enum Constants {
        static let lastContactSyncKey = "kTSStorageManagerOWSSyncManagerLastMessageKey"
        static let fullSyncRequestIdKey = "FullSyncRequestId"
        static let syncRequestedAppVersionKey = "SyncRequestedAppVersion"
    }

    // MARK: - Sync Requests

    @objc
    public func sendAllSyncRequestMessagesIfNecessary() -> AnyPromise {
        return AnyPromise(_sendAllSyncRequestMessages(onlyIfNecessary: true))
    }

    @objc
    public func sendAllSyncRequestMessages(timeout: TimeInterval) -> AnyPromise {
        return AnyPromise(_sendAllSyncRequestMessages(onlyIfNecessary: false)
            .timeout(seconds: timeout, substituteValue: ()))
    }

    private func _sendAllSyncRequestMessages(onlyIfNecessary: Bool) -> Promise<Void> {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return Promise(error: OWSAssertionError("Unexpectedly tried to send sync request before registration."))
        }

        return databaseStorage.write(.promise) { (transaction) -> Promise<Void> in
            let currentAppVersion = AppVersionImpl.shared.currentAppVersion4
            let syncRequestedAppVersion = {
                Self.keyValueStore().getString(
                    Constants.syncRequestedAppVersionKey,
                    transaction: transaction
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

            Self.keyValueStore().setString(
                currentAppVersion,
                key: Constants.syncRequestedAppVersionKey,
                transaction: transaction
            )

            return Promise.when(fulfilled: [
                NotificationCenter.default.observe(once: .IncomingContactSyncDidComplete).asVoid(),
                NotificationCenter.default.observe(once: .OWSSyncManagerConfigurationSyncDidComplete).asVoid(),
                NotificationCenter.default.observe(once: BlockingManager.blockedSyncDidComplete).asVoid(),
                NotificationCenter.default.observe(once: .OWSSyncManagerKeysSyncDidComplete).asVoid()
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

        databaseStorage.asyncWrite { [weak self] transaction in
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

        let storageServiceKey = DependenciesBridge.shared.svr.data(for: .storageService, transaction: tx.asV2Read)
        let masterKey = DependenciesBridge.shared.svr.masterKeyDataForKeysSyncMessage(tx: tx.asV2Read)
        let syncKeysMessage = OWSSyncKeysMessage(
            thread: thread,
            storageServiceKey: storageServiceKey?.rawData,
            masterKey: masterKey,
            transaction: tx
        )
        self.sskJobQueues.messageSenderJobQueue.add(message: syncKeysMessage.asPreparer, transaction: tx)
    }

    @objc
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
        } else {
            DependenciesBridge.shared.svr.storeSyncedStorageServiceKey(
                data: syncMessage.storageService,
                authedAccount: .implicit(),
                transaction: transaction.asV2Write
            )
        }

        transaction.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(.OWSSyncManagerKeysSyncDidComplete, object: nil)
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
            DispatchQueue.global().async {
                self.profileManager.fetchLocalUsersProfile(authedAccount: .implicit())
            }
        case .storageManifest:
            storageServiceManager.restoreOrCreateManifestIfNecessary(authedDevice: .implicit)
        case .subscriptionStatus:
            SubscriptionManagerImpl.performDeviceSubscriptionExpiryUpdate()
        }
    }

    @objc
    public func processIncomingMessageRequestResponseSyncMessage(
        _ syncMessage: SSKProtoSyncMessageMessageRequestResponse,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let thread: TSThread = {
            if let groupId = syncMessage.groupID {
                TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)
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
            blockingManager.removeBlockedThread(thread, wasLocallyInitiated: false, transaction: transaction)
            if let thread = thread as? TSContactThread {
                /// When we accept a message request on a linked device,
                /// we unhide the message sender. We will eventually also
                /// learn about the unhide via a StorageService contact sync,
                /// since the linked device should mark unhidden in
                /// StorageService. But it doesn't hurt to get ahead of the
                /// game and unhide here.
                DependenciesBridge.shared.recipientHidingManager.removeHiddenRecipient(
                    thread.contactAddress,
                    wasLocallyInitiated: false,
                    tx: transaction.asV2Write
                )
            }
            profileManager.addThread(toProfileWhitelist: thread, transaction: transaction)
        case .delete:
            thread.softDelete(with: transaction)
        case .block:
            blockingManager.addBlockedThread(thread, blockMode: .remote, transaction: transaction)
        case .blockAndDelete:
            thread.softDelete(with: transaction)
            blockingManager.addBlockedThread(thread, blockMode: .remote, transaction: transaction)
        case .unknown, .none:
            owsFailDebug("unexpected message request response type")
        }
    }

    public func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType) {
        Logger.info("")

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return owsFailDebug("Unexpectedly tried to send sync message before registration.")
        }

        databaseStorage.asyncWrite { [weak self] transaction in
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
        sskJobQueues.messageSenderJobQueue.add(message: syncMessageRequestResponse.asPreparer, transaction: transaction)
    }

    // MARK: - Contact Sync

    public func syncLocalContact() -> AnyPromise {
        owsAssertDebug(canSendContactSyncMessage())
        return AnyPromise(syncContacts(mode: .localAddress))
    }

    public func syncAllContacts() -> AnyPromise {
        owsAssertDebug(canSendContactSyncMessage())
        return AnyPromise(syncContacts(mode: .allSignalAccounts))
    }

    @objc
    func syncAllContactsIfNecessary() {
        owsAssertDebug(CurrentAppContext().isMainApp)
        _ = syncContacts(mode: .allSignalAccountsIfChanged)
    }

    public func syncAllContactsIfFullSyncRequested() -> AnyPromise {
        owsAssertDebug(CurrentAppContext().isMainApp)
        return AnyPromise(syncContacts(mode: .allSignalAccountsIfFullSyncRequested))
    }

    private enum ContactSyncMode {
        case localAddress
        case allSignalAccounts
        case allSignalAccountsIfChanged
        case allSignalAccountsIfFullSyncRequested
    }

    private func canSendContactSyncMessage() -> Bool {
        guard AppReadiness.isAppReady else {
            return false
        }
        guard contactsManagerImpl.isSetup else {
            return false
        }
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice else {
            return false
        }
        return true
    }

    private static let contactSyncQueue = DispatchQueue(label: "org.signal.contact-sync", autoreleaseFrequency: .workItem)

    private func syncContacts(mode: ContactSyncMode) -> Promise<Void> {
        if DebugFlags.dontSendContactOrGroupSyncMessages.get() {
            Logger.info("Skipping contact sync message.")
            return .value(())
        }

        guard canSendContactSyncMessage() else {
            return Promise(error: OWSGenericError("Not ready to sync contacts."))
        }

        return Promise { future in
            Self.contactSyncQueue.async {
                do {
                    future.resolve(on: SyncScheduler(), with: try self._syncContacts(mode: mode))
                } catch {
                    future.reject(error)
                }
            }
        }
    }

    private func _syncContacts(mode: ContactSyncMode) throws -> Promise<Void> {
        // Don't bother sending sync messages with the same data as the last
        // successfully sent contact sync message.
        let opportunistic = mode == .allSignalAccountsIfChanged
        // Only have one sync message in flight at a time.
        let debounce = mode == .allSignalAccountsIfChanged

        if debounce, self.isRequestInFlight {
            // De-bounce. It's okay if we ignore some new changes;
            // `syncAllContactsIfNecessary` is called fairly often so we'll sync soon.
            return .value(())
        }

        if CurrentAppContext().isNSE {
            // If a full sync is specifically requested in the NSE, mark it so that the
            // main app can send that request the next time in runs.
            if mode == .allSignalAccounts {
                databaseStorage.write { tx in
                    Self.keyValueStore().setString(UUID().uuidString, key: Constants.fullSyncRequestIdKey, transaction: tx)
                }
            }
            // If a full sync sync is requested in NSE, ignore it. Opportunistic syncs
            // shouldn't be requested, but this guards against cases where they are.
            return .value(())
        }

        guard let thread = TSContactThread.getOrCreateLocalThreadWithSneakyTransaction() else {
            owsFailDebug("Missing thread.")
            throw OWSError(error: .contactSyncFailed, description: "Could not sync contacts.", isRetryable: false)
        }

        let result = try databaseStorage.read { tx in try buildContactSyncMessage(in: thread, mode: mode, tx: tx) }
        guard let result else {
            return .value(())
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
            return .value(())
        }

        let dataSource = try DataSourcePath.dataSource(with: result.syncFileUrl, shouldDeleteOnDeallocation: true)

        switch mode {
        case .localAddress:
            sskJobQueues.messageSenderJobQueue.add(
                mediaMessage: result.message,
                dataSource: dataSource,
                contentType: OWSMimeTypeApplicationOctetStream,
                sourceFilename: nil,
                caption: nil,
                albumMessageId: nil,
                isTemporaryAttachment: true
            )
            return .value(())
        case .allSignalAccounts, .allSignalAccountsIfChanged, .allSignalAccountsIfFullSyncRequested:
            if debounce {
                self.isRequestInFlight = true
            }
            let (promise, future) = Promise<Void>.pending()
            messageSender.sendTemporaryAttachment(
                dataSource,
                contentType: OWSMimeTypeApplicationOctetStream,
                in: result.message,
                success: {
                    Logger.info("Successfully sent contacts sync message.")
                    self.databaseStorage.write { tx in
                        Self.keyValueStore().setData(messageHash, key: Constants.lastContactSyncKey, transaction: tx)
                        self.clearFullSyncRequestId(ifMatches: result.fullSyncRequestId, tx: tx)
                    }
                    Self.contactSyncQueue.async {
                        if debounce {
                            self.isRequestInFlight = false
                        }
                        future.resolve(())
                    }
                },
                failure: { error in
                    Logger.warn("Failed to send contacts sync message: \(error)")
                    Self.contactSyncQueue.async {
                        if debounce {
                            self.isRequestInFlight = false
                        }
                        future.reject(error)
                    }
                }
            )
            return promise
        }
    }

    private struct BuildContactSyncMessageResult {
        var message: OWSSyncContactsMessage
        var syncFileUrl: URL
        var fullSyncRequestId: String?
        var previousMessageHash: Data?
    }

    private func buildContactSyncMessage(
        in thread: TSThread,
        mode: ContactSyncMode,
        tx: SDSAnyReadTransaction
    ) throws -> BuildContactSyncMessageResult? {
        let isFullSync = mode != .localAddress

        // If we're doing a full sync, check if there's a pending request from the
        // NSE. Any full sync in the main app can clear this flag, even if it's not
        // started in response to calling syncAllContactsIfFullSyncRequested.
        var fullSyncRequestId: String?
        if isFullSync {
            fullSyncRequestId = Self.keyValueStore().getString(Constants.fullSyncRequestIdKey, transaction: tx)
        }
        // However, only syncAllContactsIfFullSyncRequested-initiated requests
        // should be skipped if there's no request.
        if mode == .allSignalAccountsIfFullSyncRequested, fullSyncRequestId == nil {
            return nil
        }

        let message = OWSSyncContactsMessage(thread: thread, isFullSync: isFullSync, tx: tx)
        guard let syncFileUrl = ContactSyncAttachmentBuilder.buildAttachmentFile(
            for: message,
            blockingManager: Self.blockingManager,
            contactsManager: Self.contactsManagerImpl,
            tx: tx
        ) else {
            owsFailDebug("Failed to serialize contacts sync message.")
            throw OWSError(error: .contactSyncFailed, description: "Could not sync contacts.", isRetryable: false)
        }
        return BuildContactSyncMessageResult(
            message: message,
            syncFileUrl: syncFileUrl,
            fullSyncRequestId: fullSyncRequestId,
            previousMessageHash: Self.keyValueStore().getData(Constants.lastContactSyncKey, transaction: tx)
        )
    }

    private func clearFullSyncRequestId(ifMatches requestId: String?, tx: SDSAnyWriteTransaction) {
        guard let requestId else {
            return
        }
        let storedRequestId = Self.keyValueStore().getString(Constants.fullSyncRequestIdKey, transaction: tx)
        // If the requestId we just finished matches the one in the database, we've
        // fulfilled the contract with the NSE. If the NSE triggers *another* sync
        // while this is outstanding, the match will fail, and we'll kick off
        // another sync at the next opportunity.
        if storedRequestId == requestId {
            Self.keyValueStore().removeValue(forKey: Constants.fullSyncRequestIdKey, transaction: tx)
        }
    }
}

// MARK: -

public extension OWSSyncManager {

    func sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeoutSeconds: TimeInterval) -> Promise<[String]> {
        Logger.info("")
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return Promise(error: OWSAssertionError("Unexpectedly tried to send sync request before registration."))
        }

        databaseStorage.asyncWrite { transaction in
            self.sendSyncRequestMessage(.blocked, transaction: transaction)
            self.sendSyncRequestMessage(.configuration, transaction: transaction)
            self.sendSyncRequestMessage(.contacts, transaction: transaction)
        }

        let notificationsPromise: Promise<([(threadId: String, sortOrder: UInt32)], Void, Void)> = Promise.when(fulfilled:
            NotificationCenter.default.observe(once: .IncomingContactSyncDidComplete).map { $0.newThreads }.timeout(seconds: timeoutSeconds, substituteValue: []),
            NotificationCenter.default.observe(once: .OWSSyncManagerConfigurationSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds),
            NotificationCenter.default.observe(once: BlockingManager.blockedSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds)
        )

        return notificationsPromise.map { (newContactThreads, _, _) -> [String] in
            var newThreads: [String: UInt32] = [:]

            for newThread in newContactThreads {
                assert(newThreads[newThread.threadId] == nil)
                newThreads[newThread.threadId] = newThread.sortOrder
            }

            return newThreads.sorted { (lhs: (key: String, value: UInt32), rhs: (key: String, value: UInt32)) -> Bool in
                lhs.value < rhs.value
            }.map { $0.key }
        }
    }

    @objc
    fileprivate func sendSyncRequestMessage(_ requestType: SSKProtoSyncMessageRequestType,
                                            transaction: SDSAnyWriteTransaction) {
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

        let syncRequestMessage = OWSSyncRequestMessage(thread: thread, requestType: requestType, transaction: transaction)
        sskJobQueues.messageSenderJobQueue.add(message: syncRequestMessage.asPreparer, transaction: transaction)
    }
}

// MARK: -

private extension Notification {
    var newThreads: [(threadId: String, sortOrder: UInt32)] {
        switch self.object {
        case let contactSync as IncomingContactSyncOperation:
            return contactSync.newThreads
        default:
            owsFailDebug("unexpected object: \(String(describing: self.object))")
            return []
        }
    }
}
