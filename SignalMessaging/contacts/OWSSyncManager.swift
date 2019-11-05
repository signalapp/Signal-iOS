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
    func objc_sendAllSyncRequestMessages() -> AnyPromise {
        return AnyPromise(_sendAllSyncRequestMessages())
    }

    @objc
    func objc_sendAllSyncRequestMessages(timeout: TimeInterval) -> AnyPromise {
        return AnyPromise(_sendAllSyncRequestMessages()
            .asVoid()
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
        }

        return when(fulfilled: [
            NotificationCenter.default.observe(once: .IncomingContactSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: .IncomingGroupSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: .OWSSyncManagerConfigurationSyncDidComplete).asVoid(),
            NotificationCenter.default.observe(once: Notification.Name(OWSBlockingManagerBlockedSyncDidComplete)).asVoid()
        ])
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
}
