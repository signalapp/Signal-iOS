//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum StickerPackOperationType: UInt {
    case install = 0
    case remove = 1
}

@objc(OWSStickerPackSyncMessage)
final class StickerPackSyncMessage: OWSOutgoingSyncMessage {
    private var packs: [StickerPackInfo] = []
    private var operationType: StickerPackOperationType = .install

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.operationType.rawValue), forKey: "operationType")
        coder.encode(packs, forKey: "packs")
    }

    required init?(coder: NSCoder) {
        let operationType = (coder.decodeObject(of: NSNumber.self, forKey: "operationType")?.uintValue).flatMap(StickerPackOperationType.init(rawValue:))
        guard let operationType else {
            return nil
        }
        self.operationType = operationType
        let packs = coder.decodeArrayOfObjects(ofClass: StickerPackInfo.self, forKey: "packs")
        guard let packs else {
            return nil
        }
        self.packs = packs
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.operationType)
        hasher.combine(self.packs)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.operationType == object.operationType else { return false }
        guard self.packs == object.packs else { return false }
        return true
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.operationType = self.operationType
        result.packs = self.packs
        return result
    }

    init(
        localThread: TSContactThread,
        packs: [StickerPackInfo],
        operationType: StickerPackOperationType,
        tx: DBReadTransaction,
    ) {
        self.packs = packs
        self.operationType = operationType
        super.init(localThread: localThread, transaction: tx)
    }

    override func syncMessageBuilder(transaction: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let operationType: SSKProtoSyncMessageStickerPackOperationType
        switch self.operationType {
        case .install:
            operationType = .install
        case .remove:
            operationType = .remove
        }

        let syncMessageBuilder = SSKProtoSyncMessage.builder()

        for pack in self.packs {
            let packOperationBuilder = SSKProtoSyncMessageStickerPackOperation.builder(packID: pack.packId, packKey: pack.packKey)
            packOperationBuilder.setType(operationType)

            do {
                syncMessageBuilder.addStickerPackOperation(try packOperationBuilder.build())
            } catch {
                owsFailDebug("couldn't build sticker pack operation: \(error)")
                return nil
            }
        }

        return syncMessageBuilder
    }

    override var isUrgent: Bool { false }

    override var contentHint: SealedSenderContentHint { .implicit }
}
