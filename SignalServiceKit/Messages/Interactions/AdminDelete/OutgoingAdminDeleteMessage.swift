//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public final class OutgoingAdminDeleteMessage: TransientOutgoingMessage {
    let originalMessageTimestamp: UInt64
    let originalMessageAuthor: Aci?
    let originalMessageUniqueId: String

    public init(
        thread: TSThread,
        message: TSMessage,
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
    ) {
        owsAssertDebug(thread.uniqueId == message.uniqueThreadId)

        self.originalMessageTimestamp = message.timestamp

        if let incomingMessage = message as? TSIncomingMessage {
            self.originalMessageAuthor = incomingMessage.authorAddress.aci
        } else {
            self.originalMessageAuthor = localIdentifiers.aci
        }

        self.originalMessageUniqueId = message.uniqueId

        super.init(
            outgoingMessageWith: TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override public class var supportsSecureCoding: Bool { true }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.originalMessageTimestamp), forKey: "originalMessageTimestamp")
        if let originalMessageAuthor {
            coder.encode(originalMessageAuthor.serviceIdBinary, forKey: "originalMessageAuthorBinary")
        }
        coder.encode(originalMessageUniqueId, forKey: "originalMessageUniqueId")
    }

    public required init?(coder: NSCoder) {
        guard
            let originalMessageTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "originalMessageTimestamp"),
            let originalMessageAuthorBinary = coder.decodeObject(of: NSData.self, forKey: "originalMessageAuthorBinary") as Data?,
            let originalMessageUniqueId = coder.decodeObject(of: NSString.self, forKey: "originalMessageUniqueId") as String?
        else {
            return nil
        }
        self.originalMessageTimestamp = originalMessageTimestamp.uint64Value
        self.originalMessageAuthor = try? Aci.parseFrom(serviceIdBinary: originalMessageAuthorBinary)
        self.originalMessageUniqueId = originalMessageUniqueId
        super.init(coder: coder)
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.originalMessageTimestamp)
        hasher.combine(self.originalMessageAuthor)
        hasher.combine(self.originalMessageUniqueId)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.originalMessageTimestamp == object.originalMessageTimestamp else { return false }
        guard self.originalMessageAuthor == object.originalMessageAuthor else { return false }
        guard self.originalMessageUniqueId == object.originalMessageUniqueId else { return false }
        return true
    }

    override public func dataMessageBuilder(with thread: TSThread, transaction: DBReadTransaction) -> SSKProtoDataMessageBuilder? {
        guard let originalMessageAuthor else {
            return nil
        }

        let adminDeleteBuilder = SSKProtoDataMessageAdminDelete.builder()
        adminDeleteBuilder.setTargetAuthorAciBinary(originalMessageAuthor.serviceIdBinary)
        adminDeleteBuilder.setTargetSentTimestamp(originalMessageTimestamp)

        let builder = super.dataMessageBuilder(with: thread, transaction: transaction)
        builder?.setTimestamp(self.timestamp)
        builder?.setAdminDelete(adminDeleteBuilder.buildInfallibly())
        return builder
    }

    override public func anyUpdateOutgoingMessage(transaction: DBWriteTransaction, block: (TSOutgoingMessage) -> Void) {
        super.anyUpdateOutgoingMessage(transaction: transaction, block: block)

        let deletedMessage = TSMessage.fetchMessageViaCache(
            uniqueId: originalMessageUniqueId,
            transaction: transaction,
        )
        if let outgoingDeletedMessage = deletedMessage as? TSOutgoingMessage {
            outgoingDeletedMessage.updateWithRecipientAddressStates(self.recipientAddressStates, tx: transaction)
        }

        if let deletedMessage {
            AdminDeleteManager.updateRecipientStatesAdminDelete(recipientAddressStates: self.recipientAddressStates, interactionId: deletedMessage.sqliteRowId!, tx: transaction)

            DependenciesBridge.shared.db.touch(interaction: deletedMessage, shouldReindex: false, tx: transaction)
        }
    }

    override public var relatedUniqueIds: Set<String> {
        return super.relatedUniqueIds.union([self.originalMessageUniqueId].compacted())
    }
}
