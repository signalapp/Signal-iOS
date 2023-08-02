//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

extension OWSSyncManager: SyncManagerProtocol, SyncManagerProtocolSwift {

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
        guard tsAccountManager.isRegisteredAndReady else {
            return Promise(error: OWSAssertionError("Unexpectedly tried to send sync request before registration."))
        }

        return databaseStorage.write(.promise) { (transaction) -> Promise<Void> in
            let currentAppVersion = AppVersionImpl.shared.currentAppVersion4
            let syncRequestedAppVersion = {
                Self.keyValueStore().getString(
                    OWSSyncManagerSyncRequestedAppVersionKey,
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
                key: OWSSyncManagerSyncRequestedAppVersionKey,
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

        guard tsAccountManager.isRegisteredAndReady else {
            return owsFailDebug("Unexpectedly tried to send sync request before registration.")
        }

        guard tsAccountManager.isRegisteredPrimaryDevice else {
            return owsFailDebug("Keys sync should only be initiated from the primary device")
        }

        databaseStorage.asyncWrite { [weak self] transaction in
            guard let self = self else { return }

            guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
                return owsFailDebug("Missing thread")
            }

            let storageServiceKey = DependenciesBridge.shared.svr.data(for: .storageService, transaction: transaction.asV2Read)
            let syncKeysMessage = OWSSyncKeysMessage(
                thread: thread,
                storageServiceKey: storageServiceKey?.rawData,
                transaction: transaction
            )
            self.sskJobQueues.messageSenderJobQueue.add(message: syncKeysMessage.asPreparer, transaction: transaction)
        }
    }

    @objc
    public func processIncomingKeysSyncMessage(_ syncMessage: SSKProtoSyncMessageKeys, transaction: SDSAnyWriteTransaction) {
        guard !tsAccountManager.isRegisteredPrimaryDevice else {
            return owsFailDebug("Key sync messages should only be processed on linked devices")
        }

        DependenciesBridge.shared.svr.storeSyncedStorageServiceKey(
            data: syncMessage.storageService,
            authedAccount: .implicit(),
            transaction: transaction.asV2Write
        )

        transaction.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(.OWSSyncManagerKeysSyncDidComplete, object: nil)
        }
    }

    public func sendKeysSyncRequestMessage(transaction: SDSAnyWriteTransaction) {
        sendSyncRequestMessage(.keys, transaction: transaction)
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
            if let thread = thread as? TSContactThread, FeatureFlags.recipientHiding {
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

        guard tsAccountManager.isRegisteredAndReady else {
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

        guard tsAccountManager.isRegisteredAndReady else {
            return owsFailDebug("Unexpectedly tried to send sync message before registration.")
        }

        let syncMessageRequestResponse = OWSSyncMessageRequestResponseMessage(thread: thread, responseType: responseType, transaction: transaction)
        sskJobQueues.messageSenderJobQueue.add(message: syncMessageRequestResponse.asPreparer, transaction: transaction)
    }
}

// MARK: -

public extension OWSSyncManager {

    func sendInitialSyncRequestsAwaitingCreatedThreadOrdering(timeoutSeconds: TimeInterval) -> Promise<[String]> {
        Logger.info("")
        guard tsAccountManager.isRegisteredAndReady else {
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

        guard tsAccountManager.isRegisteredAndReady else {
            return owsFailDebug("Unexpectedly tried to send sync request before registration.")
        }

        guard !tsAccountManager.isRegisteredPrimaryDevice else {
            return owsFailDebug("Sync request should only be sent from a linked device")
        }

        guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
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
