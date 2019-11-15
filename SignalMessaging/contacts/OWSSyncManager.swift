//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension OWSSyncManager {

    // MARK: -

    var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    // MARK: - Sync Requests

    @objc
    func _objc_sendAllSyncRequestMessages() -> AnyPromise {
        return AnyPromise(sendAllSyncRequestMessages())
    }

    @objc
    func _objc_sendAllSyncRequestMessages(timeout: TimeInterval) -> AnyPromise {
        return AnyPromise(sendAllSyncRequestMessages()
            .timeout(seconds: timeout, substituteValue: ()))
    }

    private func sendAllSyncRequestMessages() -> Promise<Void> {
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

        return when(fulfilled: [
            NotificationCenter.default.observe(once: .IncomingContactSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: .IncomingGroupSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: .OWSSyncManagerConfigurationSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: .OWSBlockingManagerBlockedSyncDidComplete).asVoid()
        ])
    }

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

        let notificationsPromise: Promise<([(threadId: String, sortOrder: UInt32)], [(threadId: String, sortOrder: UInt32)], Void, Void)> = when(fulfilled:
            NotificationCenter.default.observe(once: .IncomingContactSyncDidComplete).map { $0.newThreads }.timeout(seconds: timeoutSeconds, substituteValue: []),
            NotificationCenter.default.observe(once: .IncomingGroupSyncDidComplete).map { $0.newThreads }.timeout(seconds: timeoutSeconds, substituteValue: []),
            NotificationCenter.default.observe(once: .OWSSyncManagerConfigurationSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds),
            NotificationCenter.default.observe(once: .OWSBlockingManagerBlockedSyncDidComplete).asVoid().timeout(seconds: timeoutSeconds)
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

    private func sendSyncRequestMessage(_ requestType: OWSSyncRequestType, transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        guard tsAccountManager.isRegisteredAndReady else {
            return owsFailDebug("Unexpectedly tried to send sync request before registration.")
        }

        guard !tsAccountManager.isRegisteredPrimaryDevice else {
            return owsFailDebug("Sync request should only be sent from a linked device")
        }

        guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
            return owsFailDebug("Missing thread")
        }

        let syncRequestMessage = OWSSyncRequestMessage(thread: thread, requestType: requestType)
        messageSenderJobQueue.add(message: syncRequestMessage.asPreparer, transaction: transaction)
    }

    @objc
    func _objc_sendKeysSyncMessage() {
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

            let syncKeysMessage = OWSSyncKeysMessage(thread: thread, storageServiceKey: KeyBackupService.DerivedKey.storageService.data)
            self.messageSenderJobQueue.add(message: syncKeysMessage.asPreparer, transaction: transaction)
        }
    }
}

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
