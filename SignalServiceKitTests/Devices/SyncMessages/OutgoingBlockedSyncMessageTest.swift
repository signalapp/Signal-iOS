//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import Testing

@testable import SignalServiceKit

@objc(OutgoingBlockedSyncMessageV1)
private class OutgoingBlockedSyncMessageV1: NSObject, NSSecureCoding {
    let uniqueId = UUID().uuidString
    var phoneNumbers = [String]()
    var aciStrings = [String]()
    var groupIds = [Data]()

    override init() {
    }

    static var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        owsFail("not supported")
    }

    func encode(with coder: NSCoder) {
        coder.encode(uniqueId, forKey: "uniqueId")
        coder.encode(groupIds, forKey: "groupIds")
        coder.encode(aciStrings, forKey: "uuids")
        coder.encode(phoneNumbers, forKey: "phoneNumbers")
    }
}

@objc(OutgoingBlockedSyncMessageV2)
private class OutgoingBlockedSyncMessageV2: NSObject, NSSecureCoding {
    let uniqueId = UUID().uuidString
    var phoneNumbers = [String]()
    var phoneNumberBlockedAts = [UInt64]()
    var aciStrings = [String]()
    var aciStringBlockedAts = [UInt64]()
    var groupIds = [Data]()
    var groupIdBlockedAts = [UInt64]()

    override init() {
    }

    static var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        owsFail("not supported")
    }

    func encode(with coder: NSCoder) {
        coder.encode(uniqueId, forKey: "uniqueId")
        coder.encode(groupIds, forKey: "groupIds")
        coder.encode(groupIdBlockedAts, forKey: "groupIdBlockedAts")
        coder.encode(aciStrings, forKey: "uuids")
        coder.encode(aciStringBlockedAts, forKey: "aciBlockedAts")
        coder.encode(phoneNumbers, forKey: "phoneNumbers")
        coder.encode(phoneNumberBlockedAts, forKey: "phoneNumberBlockedAts")
    }
}

struct OutgoingBlockedSyncMessageTest {
    @Test
    func testLegacyDecoding() throws {
        let message = OutgoingBlockedSyncMessageV1()
        message.groupIds.append(Data(repeating: 1, count: 32))
        message.phoneNumbers.append("+16505550100")
        message.aciStrings.append("00000000-0000-4000-8000-00000000000A")
        let encodedMessage = encodeOutgoingBlockedSyncMessage(message)
        let decodedMessage = try NSKeyedUnarchiver.unarchivedObject(ofClass: OutgoingBlockedSyncMessage.self, from: encodedMessage)!
        #expect(decodedMessage.groupIds == message.groupIds.map {
            return OutgoingBlockedSyncMessage.BlockedItem(rawValue: $0, blockedAt: .unspecified)
        })
        #expect(decodedMessage.phoneNumbers == message.phoneNumbers.map {
            return OutgoingBlockedSyncMessage.BlockedItem(rawValue: $0, blockedAt: .unspecified)
        })
        #expect(decodedMessage.acis == message.aciStrings.map {
            return OutgoingBlockedSyncMessage.BlockedItem(rawValue: Aci.parseFrom(aciString: $0)!, blockedAt: .unspecified)
        })
    }

    @Test
    func testDecoding() throws {
        let message = OutgoingBlockedSyncMessageV2()
        message.groupIds.append(Data(repeating: 1, count: 32))
        message.groupIdBlockedAts.append(1)
        message.phoneNumbers.append("+16505550100")
        message.phoneNumberBlockedAts.append(2)
        message.aciStrings.append("00000000-0000-4000-8000-00000000000A")
        message.aciStringBlockedAts.append(3)
        let encodedMessage = encodeOutgoingBlockedSyncMessage(message)
        let decodedMessage = try NSKeyedUnarchiver.unarchivedObject(ofClass: OutgoingBlockedSyncMessage.self, from: encodedMessage)!
        #expect(decodedMessage.groupIds == zip(message.groupIds, message.groupIdBlockedAts).map {
            return OutgoingBlockedSyncMessage.BlockedItem(rawValue: $0, blockedAt: BlockedTimestamp(clamping: $1))
        })
        #expect(decodedMessage.phoneNumbers == zip(message.phoneNumbers, message.phoneNumberBlockedAts).map {
            return OutgoingBlockedSyncMessage.BlockedItem(rawValue: $0, blockedAt: BlockedTimestamp(clamping: $1))
        })
        #expect(decodedMessage.acis == zip(message.aciStrings, message.aciStringBlockedAts).map {
            return OutgoingBlockedSyncMessage.BlockedItem(
                rawValue: Aci.parseFrom(aciString: $0)!,
                blockedAt: BlockedTimestamp(clamping: $1),
            )
        })
    }

    private func encodeOutgoingBlockedSyncMessage<T: NSObject & NSSecureCoding>(_ object: T) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("OWSBlockedPhoneNumbersMessage", for: T.self)
        archiver.encode(object, forKey: NSKeyedArchiveRootObjectKey)
        return archiver.encodedData
    }
}
