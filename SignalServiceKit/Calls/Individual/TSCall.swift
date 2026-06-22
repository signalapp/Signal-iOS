//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: - RPRecentCallType

extension RPRecentCallType: CustomStringConvertible {
    public var description: String {
        NSStringFromCallType(self)
    }
}

// MARK: - Disappearing messages

extension TSCall: ExpiringCallInteraction {
    @objc
    func ensureExpirationStarted(transaction tx: DBWriteTransaction) {
        startExpirationIfNecessary(transaction: tx)
    }
}

// MARK: - OWSReadTracking

@objc
extension TSCall: OWSReadTracking {
    public func markAsRead(
        atTimestamp readTimestamp: UInt64,
        thread: TSThread,
        circumstance: OWSReceiptCircumstance,
        shouldClearNotifications: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        if readTimestamp < expireStartedAt {
            // This device already read the item but a linked device read it earlier
            startOrUpdateExpiration(readTimestamp: readTimestamp, tx: tx)
        }

        if wasRead {
            return
        }

        anyUpdateCall(transaction: tx) { callMessage in
            callMessage.wasRead = true
        }

        switch circumstance {
        case .onThisDevice, .onThisDeviceWhilePendingMessageRequest:
            let callRecordStore = DependenciesBridge.shared.callRecordStore
            let missedCallManager = DependenciesBridge.shared.callRecordMissedCallManager

            if
                let sqliteRowId,
                let associatedCallRecord = callRecordStore.fetch(
                    interactionRowId: sqliteRowId,
                    tx: tx,
                )
            {
                missedCallManager.markUnreadCallsInConversationAsRead(
                    beforeCallRecord: associatedCallRecord,
                    sendSyncMessage: true,
                    tx: tx,
                )
            }
        case .onLinkedDevice, .onLinkedDeviceWhilePendingMessageRequest:
            // This device has not read the item but a linked device has
            startOrUpdateExpiration(readTimestamp: readTimestamp, tx: tx)
        @unknown default:
            break
        }
    }
}
