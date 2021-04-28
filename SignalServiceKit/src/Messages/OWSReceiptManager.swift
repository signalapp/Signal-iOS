//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

struct ReceiptForLinkedDevice: Codable {
    let senderAddress: SignalServiceAddress
    let messageIdTimestamp: UInt64
    let timestamp: UInt64

    var asLinkedDeviceReadReceipt: OWSLinkedDeviceReadReceipt {
        return OWSLinkedDeviceReadReceipt(senderAddress: senderAddress, messageIdTimestamp: messageIdTimestamp, readTimestamp: timestamp)
    }

    var asLinkedDeviceViewedReceipt: OWSLinkedDeviceViewedReceipt {
        return OWSLinkedDeviceViewedReceipt(senderAddress: senderAddress, messageIdTimestamp: messageIdTimestamp, viewedTimestamp: timestamp)
    }
}

// MARK: -

@objc
public extension OWSReceiptManager {

    private var toLinkedDevicesReadReceiptMapStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "OWSReceiptManager.toLinkedDevicesReadReceiptMapStore")
    }

    private var toLinkedDevicesViewedReceiptMapStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "OWSReceiptManager.toLinkedDevicesViewedReceiptMapStore")
    }

    func processReceiptsForLinkedDevices(completion: @escaping () -> Void) {
        guard !DebugFlags.suppressBackgroundActivity else {
            // Don't process queues.
            return completion()
        }

        Logger.verbose("Processing receipts for linked devices.")

        let didWork = databaseStorage.write { transaction -> Bool in
            let readReceiptsForLinkedDevices: [ReceiptForLinkedDevice]
            do {
                readReceiptsForLinkedDevices = try self.toLinkedDevicesReadReceiptMapStore.allCodableValues(transaction: transaction)
            } catch {
                owsFailDebug("Error: \(error).")
                return false
            }

            let viewedReceiptsForLinkedDevices: [ReceiptForLinkedDevice]
            do {
                viewedReceiptsForLinkedDevices = try self.toLinkedDevicesViewedReceiptMapStore.allCodableValues(transaction: transaction)
            } catch {
                owsFailDebug("Error: \(error).")
                return false
            }

            guard !readReceiptsForLinkedDevices.isEmpty || !viewedReceiptsForLinkedDevices.isEmpty else {
                return false
            }

            guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
                owsFailDebug("Missing thread.")
                return false
            }

            if !readReceiptsForLinkedDevices.isEmpty {
                let receiptsForMessage = readReceiptsForLinkedDevices.map { $0.asLinkedDeviceReadReceipt }
                let message = OWSReadReceiptsForLinkedDevicesMessage(thread: thread, readReceipts: receiptsForMessage)

                self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                self.toLinkedDevicesReadReceiptMapStore.removeAll(transaction: transaction)
            }

            if !viewedReceiptsForLinkedDevices.isEmpty {
                let receiptsForMessage = viewedReceiptsForLinkedDevices.map { $0.asLinkedDeviceViewedReceipt }
                let message = OWSViewedReceiptsForLinkedDevicesMessage(thread: thread, viewedReceipts: receiptsForMessage)

                self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                self.toLinkedDevicesViewedReceiptMapStore.removeAll(transaction: transaction)
            }

            return true
        }

        if didWork {
            // Wait N seconds before processing read receipts again.
            // This allows time for a batch to accumulate.
            //
            // We want a value high enough to allow us to effectively de-duplicate,
            // read receipts without being so high that we risk not sending read
            // receipts due to app exit.
            let kProcessingFrequencySeconds: TimeInterval = 3
            DispatchQueue.global().asyncAfter(deadline: .now() + kProcessingFrequencySeconds) {
                self.processReceiptsForLinkedDevices(completion: completion)
            }
        } else {
            completion()
        }
    }

    func sendLinkedDeviceReadReceipt(forMessages messages: [TSOutgoingMessage],
                                     thread: TSThread,
                                     transaction: SDSAnyWriteTransaction) {
        assert(messages.count > 0)
        guard let localAddress = TSAccountManager.localAddress else {
            return owsFailDebug("missing local address")
        }
        let readTimestamp = Date.ows_millisecondTimestamp()
        let receiptsForMessage = messages.map {
            OWSLinkedDeviceReadReceipt(
                senderAddress: localAddress,
                messageIdTimestamp: $0.timestamp,
                readTimestamp: readTimestamp
            )
        }
        let message = OWSReadReceiptsForLinkedDevicesMessage(thread: thread, readReceipts: receiptsForMessage)
        self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
    }

    func enqueueLinkedDeviceReadReceipt(forMessage message: TSIncomingMessage,
                                        transaction: SDSAnyWriteTransaction) {
        let threadUniqueId = message.uniqueThreadId

        let messageAuthorAddress = message.authorAddress
        assert(messageAuthorAddress.isValid)

        let newReadReceipt = ReceiptForLinkedDevice(
            senderAddress: messageAuthorAddress,
            messageIdTimestamp: message.timestamp,
            timestamp: Date.ows_millisecondTimestamp()
        )

        do {
            if let oldReadReceipt: ReceiptForLinkedDevice = try toLinkedDevicesReadReceiptMapStore.getCodableValue(forKey: threadUniqueId, transaction: transaction),
                oldReadReceipt.messageIdTimestamp > newReadReceipt.messageIdTimestamp {
                // If there's an existing "linked device" read receipt for the same thread with
                // a newer timestamp, discard this "linked device" read receipt.
                Logger.verbose("Ignoring redundant read receipt for linked devices.")
            } else {
                Logger.verbose("Enqueuing read receipt for linked devices.")
                try toLinkedDevicesReadReceiptMapStore.setCodable(newReadReceipt, key: threadUniqueId, transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error).")
        }
    }

    func enqueueLinkedDeviceViewedReceipt(forMessage message: TSIncomingMessage,
                                        transaction: SDSAnyWriteTransaction) {
        let threadUniqueId = message.uniqueThreadId

        let messageAuthorAddress = message.authorAddress
        assert(messageAuthorAddress.isValid)

        let newViewedReceipt = ReceiptForLinkedDevice(
            senderAddress: messageAuthorAddress,
            messageIdTimestamp: message.timestamp,
            timestamp: Date.ows_millisecondTimestamp()
        )

        do {
            if let oldViewedReceipt: ReceiptForLinkedDevice = try toLinkedDevicesViewedReceiptMapStore.getCodableValue(forKey: threadUniqueId, transaction: transaction),
                oldViewedReceipt.messageIdTimestamp > newViewedReceipt.messageIdTimestamp {
                // If there's an existing "linked device" viewed receipt for the same thread with
                // a newer timestamp, discard this "linked device" read receipt.
                Logger.verbose("Ignoring redundant viewed receipt for linked devices.")
            } else {
                Logger.verbose("Enqueuing viewed receipt for linked devices.")
                try toLinkedDevicesViewedReceiptMapStore.setCodable(newViewedReceipt, key: threadUniqueId, transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error).")
        }
    }
}
