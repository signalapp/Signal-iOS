//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSViewOnceMessageReadSyncMessage)
final class OutgoingViewOnceOpenSyncMessage: OutgoingSyncMessage {

    let senderAddress: SignalServiceAddress
    let messageIdTimestamp: UInt64
    let readTimestamp: UInt64
    let messageUniqueId: String? // Only nil if decoding old values

    init(
        localThread: TSContactThread,
        senderAci: Aci,
        message: TSMessage,
        readTimestamp: UInt64,
        tx: DBReadTransaction,
    ) {
        owsAssertDebug(message.timestamp > 0)
        self.senderAddress = SignalServiceAddress(senderAci)
        self.messageUniqueId = message.uniqueId
        self.messageIdTimestamp = message.timestamp
        self.readTimestamp = readTimestamp
        super.init(localThread: localThread, tx: tx)
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.messageIdTimestamp), forKey: "messageIdTimestamp")
        if let messageUniqueId {
            coder.encode(messageUniqueId, forKey: "messageUniqueId")
        }
        coder.encode(NSNumber(value: self.readTimestamp), forKey: "readTimestamp")
        coder.encode(self.senderAddress, forKey: "senderAddress")
    }

    required init?(coder: NSCoder) {
        guard let messageIdTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "messageIdTimestamp") else {
            return nil
        }
        self.messageIdTimestamp = messageIdTimestamp.uint64Value
        self.messageUniqueId = coder.decodeObject(of: NSString.self, forKey: "messageUniqueId") as String?
        guard let readTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "readTimestamp") else {
            return nil
        }
        self.readTimestamp = readTimestamp.uint64Value
        let modernAddress = coder.decodeObject(of: SignalServiceAddress.self, forKey: "senderAddress")
        self.senderAddress = modernAddress ?? SignalServiceAddress.legacyAddress(
            serviceIdString: nil,
            phoneNumber: coder.decodeObject(of: NSString.self, forKey: "senderId") as String?,
        )
        owsAssertDebug(self.senderAddress.isValid)
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.messageIdTimestamp)
        hasher.combine(self.messageUniqueId)
        hasher.combine(self.readTimestamp)
        hasher.combine(self.senderAddress)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.messageIdTimestamp == object.messageIdTimestamp else { return false }
        guard self.messageUniqueId == object.messageUniqueId else { return false }
        guard self.readTimestamp == object.readTimestamp else { return false }
        guard self.senderAddress == object.senderAddress else { return false }
        return true
    }

    override var isUrgent: Bool { false }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let syncMessageBuilder = SSKProtoSyncMessage.builder()

        let readProtoBuilder = SSKProtoSyncMessageViewOnceOpen.builder(timestamp: self.messageIdTimestamp)
        if let senderAci = self.senderAddress.serviceId as? Aci {
            readProtoBuilder.setSenderAciBinary(senderAci.serviceIdBinary)
        } else {
            owsFailDebug("can't send view once open sync for message without an ACI")
        }

        do {
            let readProto = try readProtoBuilder.build()
            syncMessageBuilder.setViewOnceOpen(readProto)
            return syncMessageBuilder
        } catch {
            owsFailDebug("could not build protobuf: \(error)")
            return nil
        }
    }

    override var relatedUniqueIds: Set<String> {
        return super.relatedUniqueIds.union([self.messageUniqueId].compacted())
    }
}
