//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSSyncManager: SyncManagerProtocolSwift {

    // MARK: - Sync Requests

    @objc
    public func sendAllSyncRequestMessages() -> AnyPromise {
        return AnyPromise(_sendAllSyncRequestMessages())
    }

    @objc
    public func sendAllSyncRequestMessages(timeout: TimeInterval) -> AnyPromise {
        return AnyPromise(_sendAllSyncRequestMessages()
            .timeout(seconds: timeout, substituteValue: ()))
    }

    private func _sendAllSyncRequestMessages() -> Promise<Void> {
        Logger.info("")

        guard tsAccountManager.isRegisteredAndReady else {
            return Promise(error: OWSAssertionError("Unexpectedly tried to send sync request before registration."))
        }

        databaseStorage.asyncWrite { transaction in
            self.sendSyncRequestMessage(.blocked, transaction: transaction)
            self.sendSyncRequestMessage(.configuration, transaction: transaction)
            self.sendSyncRequestMessage(.groups, transaction: transaction)
            self.sendSyncRequestMessage(.contacts, transaction: transaction)
            self.sendSyncRequestMessage(.keys, transaction: transaction)
        }

        return Promise.when(fulfilled: [
            NotificationCenter.default.observe(once: .IncomingContactSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: .IncomingGroupSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: .OWSSyncManagerConfigurationSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: BlockingManager.blockedSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: .OWSSyncManagerKeysSyncDidComplete).asVoid()
        ])
    }

    @objc
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

            let syncKeysMessage = OWSSyncKeysMessage(thread: thread, storageServiceKey: KeyBackupService.DerivedKey.storageService.data, transaction: transaction)
            self.messageSenderJobQueue.add(message: syncKeysMessage.asPreparer, transaction: transaction)
        }
    }

    @objc
    public func processIncomingKeysSyncMessage(_ syncMessage: SSKProtoSyncMessageKeys, transaction: SDSAnyWriteTransaction) {
        guard !tsAccountManager.isRegisteredPrimaryDevice else {
            return owsFailDebug("Key sync messages should only be processed on linked devices")
        }

        KeyBackupService.storeSyncedKey(type: .storageService, data: syncMessage.storageService, transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(.OWSSyncManagerKeysSyncDidComplete, object: nil)
        }
    }

    @objc
    public func sendKeysSyncRequestMessage(transaction: SDSAnyWriteTransaction) {
        sendSyncRequestMessage(.keys, transaction: transaction)
    }

    private static let pniIdentitySyncMessagePending = AtomicBool(false)

    @objc
    public func sendPniIdentitySyncMessage() {
        Logger.info("")

        guard Self.pniIdentitySyncMessagePending.tryToSetFlag() else {
            // Already scheduled!
            return
        }

        _ = messageProcessor.fetchingAndProcessingCompletePromise().done(on: .global()) {
            guard self.tsAccountManager.isRegisteredAndReady else {
                return owsFailDebug("Unexpectedly tried to send sync message before registration.")
            }

            guard self.tsAccountManager.isRegisteredPrimaryDevice else {
                return owsFailDebug("PNI identity sync should only be initiated from the primary device")
            }

            self.databaseStorage.write { transaction in
                guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
                    return owsFailDebug("Missing thread")
                }

                guard let keyPair = self.identityManager.identityKeyPair(for: .pni) else {
                    Logger.warn("no PNI identity key yet; ignoring request")
                    return
                }
                let syncMessage = OWSSyncPniIdentityMessage(thread: thread, keyPair: keyPair, transaction: transaction)
                Self.pniIdentitySyncMessagePending.set(false)
                self.messageSenderJobQueue.add(message: syncMessage.asPreparer, transaction: transaction)
            }
        }
    }

    @objc
    public func processIncomingMessageRequestResponseSyncMessage(
        _ syncMessage: SSKProtoSyncMessageMessageRequestResponse,
        transaction: SDSAnyWriteTransaction
    ) {
        let thread: TSThread
        if let groupId = syncMessage.groupID {
            TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)
            guard let groupThread = TSGroupThread.fetch(groupId: groupId,
                                                        transaction: transaction) else {
                return owsFailDebug("message request response for missing group thread")
            }
            thread = groupThread
        } else if let threadAddress = syncMessage.threadAddress {
            guard let contactThread = TSContactThread.getWithContactAddress(threadAddress, transaction: transaction) else {
                return owsFailDebug("message request response for missing thread")
            }
            thread = contactThread
        } else {
            return owsFailDebug("message request response missing group or contact thread information")
        }

        guard let type = syncMessage.type else { return owsFailDebug("messasge request response missing type") }

        switch type {
        case .accept:
            blockingManager.removeBlockedThread(thread, wasLocallyInitiated: false, transaction: transaction)
            profileManager.addThread(toProfileWhitelist: thread, transaction: transaction)
        case .delete:
            thread.softDelete(with: transaction)
        case .block:
            blockingManager.addBlockedThread(thread, blockMode: .remote, transaction: transaction)
        case .blockAndDelete:
            thread.softDelete(with: transaction)
            blockingManager.addBlockedThread(thread, blockMode: .remote, transaction: transaction)
        case .unknown:
            owsFailDebug("unexpected message request response type")
        }
    }

    @objc
    public func sendMessageRequestResponseSyncMessage(thread: TSThread, responseType: OWSSyncMessageRequestResponseType) {
        Logger.info("")

        guard tsAccountManager.isRegisteredAndReady else {
            return owsFailDebug("Unexpectedly tried to send sync message before registration.")
        }

        databaseStorage.asyncWrite { [weak self] transaction in
            self?.sendMessageRequestResponseSyncMessage(thread: thread, responseType: responseType, transaction: transaction)
        }
    }

    @objc
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
        messageSenderJobQueue.add(message: syncMessageRequestResponse.asPreparer, transaction: transaction)
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
            self.sendSyncRequestMessage(.groups, transaction: transaction)
            self.sendSyncRequestMessage(.contacts, transaction: transaction)
        }

        let notificationsPromise: Promise<([(threadId: String, sortOrder: UInt32)], [(threadId: String, sortOrder: UInt32)], Void, Void)> = Promise.when(fulfilled:
            NotificationCenter.default.observe(once: .IncomingContactSyncDidComplete).map { $0.newThreads }.timeout(seconds: timeoutSeconds, substituteValue: []),
            NotificationCenter.default.observe(once: .IncomingGroupSyncDidComplete).map { $0.newThreads }.timeout(seconds: timeoutSeconds, substituteValue: []),
            NotificationCenter.default.observe(once: .OWSSyncManagerConfigurationSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds),
            NotificationCenter.default.observe(once: BlockingManager.blockedSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds)
        )

        return notificationsPromise.map { (newContactThreads, newGroupThreads, _, _) -> [String] in
            var newThreads: [String: UInt32] = [:]

            for newThread in newContactThreads {
                assert(newThreads[newThread.threadId] == nil)
                newThreads[newThread.threadId] = newThread.sortOrder
            }

            for newThread in newGroupThreads {
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
        case .groups:
            Logger.info("groups")
        case .blocked:
            Logger.info("blocked")
        case .configuration:
            Logger.info("configuration")
        case .keys:
            Logger.info("keys")
        case .pniIdentity:
            Logger.info("pniIdentity")
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
        messageSenderJobQueue.add(message: syncRequestMessage.asPreparer, transaction: transaction)
    }
}

// MARK: -

private extension Notification {
    var newThreads: [(threadId: String, sortOrder: UInt32)] {
        switch self.object {
        case let groupSync as IncomingGroupSyncOperation:
            return groupSync.newThreads
        case let contactSync as IncomingContactSyncOperation:
            return contactSync.newThreads
        default:
            owsFailDebug("unexpected object: \(String(describing: self.object))")
            return []
        }
    }
}
