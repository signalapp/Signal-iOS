//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSViewedReceiptsForLinkedDevicesMessage)
final class OutgoingViewedReceiptsSyncMessage: OutgoingSyncMessage {

    let viewedReceipts: [LinkedDeviceViewedReceipt]

    init(
        localThread: TSContactThread,
        viewedReceipts: [LinkedDeviceViewedReceipt],
        tx: DBReadTransaction,
    ) {
        self.viewedReceipts = viewedReceipts
        super.init(localThread: localThread, tx: tx)
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(viewedReceipts, forKey: "viewedReceipts")
    }

    required init?(coder: NSCoder) {
        guard let viewedReceipts = coder.decodeArrayOfObjects(ofClass: LinkedDeviceViewedReceipt.self, forKey: "viewedReceipts") else {
            return nil
        }
        self.viewedReceipts = viewedReceipts
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.viewedReceipts)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.viewedReceipts == object.viewedReceipts else { return false }
        return true
    }

    override var isUrgent: Bool { false }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        for viewedReceipt in self.viewedReceipts {
            let viewedProtoBuilder = SSKProtoSyncMessageViewed.builder(timestamp: viewedReceipt.messageIdTimestamp)

            if let aci = viewedReceipt.senderAddress.serviceId as? Aci {
                viewedProtoBuilder.setSenderAciBinary(aci.serviceIdBinary)
            } else {
                owsFailDebug("can't send viewed receipt for message without an ACI")
            }

            do {
                syncMessageBuilder.addViewed(try viewedProtoBuilder.build())
            } catch {
                owsFailDebug("could not build protobuf: \(error)")
                return nil
            }
        }
        return syncMessageBuilder
    }

    override var relatedUniqueIds: Set<String> {
        return super.relatedUniqueIds.union(self.viewedReceipts.lazy.compactMap(\.messageUniqueId))
    }
}
