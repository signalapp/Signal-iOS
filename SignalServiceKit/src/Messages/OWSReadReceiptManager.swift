//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

struct ReadReceiptForLinkedDevice: Codable {
    let senderAddress: SignalServiceAddress
    let messageIdTimestamp: UInt64
    let readTimestamp: UInt64

    var asLinkedDeviceReadReceipt: OWSLinkedDeviceReadReceipt {
        return OWSLinkedDeviceReadReceipt(senderAddress: senderAddress, messageIdTimestamp: messageIdTimestamp, readTimestamp: readTimestamp)
    }
}

// MARK: -

@objc
public extension OWSReadReceiptManager {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    // MARK: -

    private var toLinkedDevicesReadReceiptMapStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "OWSReadReceiptManager.toLinkedDevicesReadReceiptMapStore")
    }

    func processReadReceiptsForLinkedDevices(completion: @escaping () -> Void) {
        guard !DebugFlags.suppressBackgroundActivity else {
            // Don't process queues.
            return completion()
        }

        Logger.verbose("Processing read receipts for linked devices.")

        let didWork = databaseStorage.write { transaction -> Bool in
            let readReceiptsForLinkedDevices: [ReadReceiptForLinkedDevice]
            do {
                readReceiptsForLinkedDevices = try self.toLinkedDevicesReadReceiptMapStore.allValuesAsReadReceiptForLinkedDevice(transaction: transaction)
            } catch {
                owsFailDebug("Error: \(error).")
                return false
            }
            guard !readReceiptsForLinkedDevices.isEmpty else {
                return false
            }

            guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
                owsFailDebug("Missing thread.")
                return false
            }

            let receiptsForMessage = readReceiptsForLinkedDevices.map { $0.asLinkedDeviceReadReceipt }
            let message = OWSReadReceiptsForLinkedDevicesMessage(thread: thread, readReceipts: receiptsForMessage)

            self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)

            self.toLinkedDevicesReadReceiptMapStore.removeAll(transaction: transaction)
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
                self.processReadReceiptsForLinkedDevices(completion: completion)
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

        let newReadReceipt = ReadReceiptForLinkedDevice(senderAddress: messageAuthorAddress,
                                                        messageIdTimestamp: message.timestamp,
                                                        readTimestamp: Date.ows_millisecondTimestamp())

        do {
            if let oldReadReceipt = try toLinkedDevicesReadReceiptMapStore.getReadReceiptForLinkedDevice(forKey: threadUniqueId, transaction: transaction),
                oldReadReceipt.messageIdTimestamp > newReadReceipt.messageIdTimestamp {
                // If there's an existing "linked device" read receipt for the same thread with
                // a newer timestamp, discard this "linked device" read receipt.
                Logger.verbose("Ignoring redundant read receipt for linked devices.")
            } else {
                Logger.verbose("Enqueuing read receipt for linked devices.")
                try toLinkedDevicesReadReceiptMapStore.setReadReceiptForLinkedDevice(newReadReceipt, key: threadUniqueId, transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error).")
        }
    }
}

// MARK: -

private extension SDSKeyValueStore {
    func setReadReceiptForLinkedDevice(_ value: ReadReceiptForLinkedDevice, key: String, transaction: SDSAnyWriteTransaction) throws {
        try setCodable(value, key: key, transaction: transaction)
    }

    func getReadReceiptForLinkedDevice(forKey key: String, transaction: SDSAnyReadTransaction) throws -> ReadReceiptForLinkedDevice? {
        return try getCodableValue(forKey: key, transaction: transaction)
    }

    func allValuesAsReadReceiptForLinkedDevice(transaction: SDSAnyReadTransaction) throws -> [ReadReceiptForLinkedDevice] {
        return try allCodableValues(transaction: transaction)
    }
}
