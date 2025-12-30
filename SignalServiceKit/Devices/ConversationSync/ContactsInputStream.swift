//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

struct ContactDetails {
    let aci: Aci?
    let phoneNumber: E164?
    let expireTimer: UInt32
    let expireTimerVersion: UInt32
    let inboxSortOrder: UInt32?
}

class ContactsInputStream {
    var inputStream: ChunkedInputStream

    init(inputStream: ChunkedInputStream) {
        self.inputStream = inputStream
    }

    func decodeContact() throws -> ContactDetails? {
        guard !inputStream.isEmpty else {
            return nil
        }

        let contactDataLength = try inputStream.decodeSingularUInt32Field()

        guard contactDataLength > 0 else {
            owsFailDebug("Empty contactDataLength.")
            return nil
        }

        let contactData = try inputStream.decodeData(count: Int(contactDataLength))

        let contactDetails = try SignalServiceProtos_ContactDetails(serializedBytes: contactData)

        if contactDetails.hasAvatar {
            // Consume but discard the incoming contact avatar.
            _ = try inputStream.decodeData(count: Int(contactDetails.avatar.length))
        }

        let aci = Aci.parseFrom(
            serviceIdBinary: contactDetails.hasAciBinary ? contactDetails.aciBinary : nil,
            serviceIdString: contactDetails.hasAci ? contactDetails.aci : nil,
        )
        let phoneNumber = E164.expectNilOrValid(stringValue: contactDetails.hasContactE164 ? contactDetails.contactE164 : nil)

        return ContactDetails(
            aci: aci,
            phoneNumber: phoneNumber,
            expireTimer: contactDetails.expireTimer,
            expireTimerVersion: contactDetails.expireTimerVersion,
            inboxSortOrder: contactDetails.hasInboxPosition ? contactDetails.inboxPosition : nil,
        )
    }
}
