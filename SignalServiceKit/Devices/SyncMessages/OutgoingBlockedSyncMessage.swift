//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSBlockedPhoneNumbersMessage)
final class OutgoingBlockedSyncMessage: OutgoingSyncMessage {

    let phoneNumbers: [String]
    let acis: [Aci]
    let groupIds: [Data]

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(groupIds, forKey: "groupIds")
        coder.encode(phoneNumbers, forKey: "phoneNumbers")
        coder.encode(acis.map(\.serviceIdString), forKey: "uuids")
    }

    required init?(coder: NSCoder) {
        self.groupIds = coder.decodeArrayOfObjects(ofClass: NSData.self, forKey: "groupIds") as [Data]? ?? []
        self.phoneNumbers = coder.decodeArrayOfObjects(ofClass: NSString.self, forKey: "phoneNumbers") as [String]? ?? []
        let aciStrings = coder.decodeArrayOfObjects(ofClass: NSString.self, forKey: "uuids") as [String]? ?? []
        self.acis = aciStrings.compactMap(Aci.parseFrom(aciString:))
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.groupIds)
        hasher.combine(self.phoneNumbers)
        hasher.combine(self.acis)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.groupIds == object.groupIds else { return false }
        guard self.phoneNumbers == object.phoneNumbers else { return false }
        guard self.acis == object.acis else { return false }
        return true
    }

    init(
        localThread: TSContactThread,
        phoneNumbers: [String],
        acis: [Aci],
        groupIds: [Data],
        tx: DBReadTransaction,
    ) {
        self.phoneNumbers = phoneNumbers
        self.acis = acis
        self.groupIds = groupIds
        super.init(localThread: localThread, tx: tx)
    }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let blockedBuilder = SSKProtoSyncMessageBlocked.builder()
        blockedBuilder.setNumbers(self.phoneNumbers)
        blockedBuilder.setAcisBinary(self.acis.map(\.serviceIdBinary))
        blockedBuilder.setGroupIds(self.groupIds)

        let blockedProto = blockedBuilder.buildInfallibly()

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setBlocked(blockedProto)
        return syncMessageBuilder
    }

    override var isUrgent: Bool { false }
}
