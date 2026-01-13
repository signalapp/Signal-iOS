//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

final class ReceiptMessage: TSOutgoingMessage {
    private(set) var messageUniqueIds: Set<String> = []
    private(set) var messageTimestamps: Set<UInt64> = []
    private(set) var receiptType: SSKProtoReceiptMessageType = .delivery

    init(
        thread: TSThread,
        receiptSet: MessageReceiptSet,
        receiptType: SSKProtoReceiptMessageType,
        tx: DBReadTransaction,
    ) {
        self.messageUniqueIds = receiptSet.uniqueIds
        self.messageTimestamps = receiptSet.timestamps
        self.receiptType = receiptType
        super.init(
            outgoingMessageWith: TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        owsFail("Doesn't support serialization.")
    }

    required init?(coder: NSCoder) {
        // Doesn't support serialization.
        return nil
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.messageTimestamps)
        hasher.combine(self.messageUniqueIds)
        hasher.combine(self.receiptType)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.messageTimestamps == object.messageTimestamps else { return false }
        guard self.messageUniqueIds == object.messageUniqueIds else { return false }
        guard self.receiptType == object.receiptType else { return false }
        return true
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.messageTimestamps = self.messageTimestamps
        result.messageUniqueIds = self.messageUniqueIds
        result.receiptType = self.receiptType
        return result
    }

    override func shouldSyncTranscript() -> Bool { false }

    override var isUrgent: Bool { false }

    override func contentBuilder(thread: TSThread, transaction: DBReadTransaction) -> SSKProtoContentBuilder? {
        guard let receiptMessage = buildReceiptMessage(tx: transaction) else {
            owsFailDebug("could not build protobuf.")
            return nil
        }

        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setReceiptMessage(receiptMessage)
        return contentBuilder
    }

    private func buildReceiptMessage(tx: DBReadTransaction) -> SSKProtoReceiptMessage? {
        owsAssertDebug(self.recipientAddresses().count == 1)
        owsAssertDebug(self.messageTimestamps.count > 0)

        let builder = SSKProtoReceiptMessage.builder()
        builder.setType(self.receiptType)
        for messageTimestamp in self.messageTimestamps {
            builder.addTimestamp(messageTimestamp)
        }
        return builder.buildInfallibly()
    }

    override var shouldBeSaved: Bool { false }

    override var debugDescription: String {
        return "[\(type(of: self))] with message timestamps: \(self.messageTimestamps.count)"
    }

    override var relatedUniqueIds: Set<String> {
        return super.relatedUniqueIds.union(self.messageUniqueIds)
    }
}
