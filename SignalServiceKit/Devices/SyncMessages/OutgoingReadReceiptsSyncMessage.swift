//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSReadReceiptsForLinkedDevicesMessage)
final class OutgoingReadReceiptsSyncMessage: OutgoingSyncMessage {

    let readReceipts: [LinkedDeviceReadReceipt]

    init(
        localThread: TSContactThread,
        readReceipts: [LinkedDeviceReadReceipt],
        tx: DBReadTransaction,
    ) {
        self.readReceipts = readReceipts
        super.init(localThread: localThread, tx: tx)
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(readReceipts, forKey: "readReceipts")
    }

    required init?(coder: NSCoder) {
        guard let readReceipts = coder.decodeArrayOfObjects(ofClass: LinkedDeviceReadReceipt.self, forKey: "readReceipts") else {
            return nil
        }
        self.readReceipts = readReceipts
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.readReceipts)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.readReceipts == object.readReceipts else { return false }
        return true
    }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        for readReceipt in self.readReceipts {
            let readProtoBuilder = SSKProtoSyncMessageRead.builder(timestamp: readReceipt.messageIdTimestamp)

            if let aci = readReceipt.senderAddress.serviceId as? Aci {
                readProtoBuilder.setSenderAciBinary(aci.serviceIdBinary)
            } else {
                owsFailDebug("can't send read receipt for message without an ACI")
            }
            do {
                syncMessageBuilder.addRead(try readProtoBuilder.build())
            } catch {
                owsFailDebug("could not build protobuf: \(error)")
                return nil
            }
        }
        return syncMessageBuilder
    }

    override var relatedUniqueIds: Set<String> {
        return super.relatedUniqueIds.union(self.readReceipts.lazy.compactMap(\.messageUniqueId))
    }
}
