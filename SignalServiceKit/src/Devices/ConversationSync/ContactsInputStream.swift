//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct ContactDetails {
    public let serviceId: ServiceId?
    public let phoneNumber: E164?
    public let verifiedProto: SSKProtoVerified?
    public let profileKey: Data?
    public let isBlocked: Bool
    public let expireTimer: UInt32
    public let isArchived: Bool?
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

        let contactDetails = try SSKProtoContactDetails(serializedData: contactData)

        if let avatar = contactDetails.avatar {
            // Consume but discard the incoming contact avatar.
            var decodedData = Data()
            try inputStream.decodeData(value: &decodedData, count: Int(avatar.length))
        }

        let serviceId = ServiceId.expectNilOrValid(uuidString: contactDetails.contactUuid)
        let phoneNumber = E164.expectNilOrValid(stringValue: contactDetails.contactE164)

        return ContactDetails(
            serviceId: serviceId,
            phoneNumber: phoneNumber,
            verifiedProto: contactDetails.verified,
            profileKey: contactDetails.profileKey,
            isBlocked: contactDetails.blocked,
            expireTimer: contactDetails.expireTimer,
            isArchived: contactDetails.hasArchived ? contactDetails.archived : nil,
            inboxSortOrder: contactDetails.hasInboxPosition ? contactDetails.inboxPosition : nil
        )
    }
}
