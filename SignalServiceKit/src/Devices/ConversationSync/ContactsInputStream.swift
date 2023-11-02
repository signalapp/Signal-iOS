//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public struct ContactDetails {
    public let aci: Aci?
    public let phoneNumber: E164?
    public let expireTimer: UInt32
    public let inboxSortOrder: UInt32?
}

public class ContactsInputStream {
    var inputStream: ChunkedInputStream

    public init(inputStream: ChunkedInputStream) {
        self.inputStream = inputStream
    }

    public func decodeContact() throws -> ContactDetails? {
        guard !inputStream.isEmpty else {
            return nil
        }

        var contactDataLength: UInt32 = 0
        try inputStream.decodeSingularUInt32Field(value: &contactDataLength)

        guard contactDataLength > 0 else {
            owsFailDebug("Empty contactDataLength.")
            return nil
        }

        var contactData: Data = Data()
        try inputStream.decodeData(value: &contactData, count: Int(contactDataLength))

        let contactDetails = try SignalServiceProtos_ContactDetails(serializedData: contactData)

        if contactDetails.hasAvatar {
            // Consume but discard the incoming contact avatar.
            var decodedData = Data()
            try inputStream.decodeData(value: &decodedData, count: Int(contactDetails.avatar.length))
        }

        let aci = Aci.parseFrom(aciString: contactDetails.hasAci ? contactDetails.aci : nil)
        let phoneNumber = E164.expectNilOrValid(stringValue: contactDetails.hasContactE164 ? contactDetails.contactE164 : nil)

        return ContactDetails(
            aci: aci,
            phoneNumber: phoneNumber,
            expireTimer: contactDetails.expireTimer,
            inboxSortOrder: contactDetails.hasInboxPosition ? contactDetails.inboxPosition : nil
        )
    }
}
