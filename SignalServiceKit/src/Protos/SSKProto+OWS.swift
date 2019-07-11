//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension SSKProtoGroupDetails {
    var memberAddresses: [SignalServiceAddress] {
        // Parse legacy pre-uuid group members that are not represented in the members list
        let legacyMembers = membersE164.filter { e164 in members.first { $0.e164 == e164 } == nil }.map { SignalServiceAddress(phoneNumber: $0) }

        return members.map { member in
            let uuidString: String?
            if let uuid = member.uuid, !uuid.isEmpty {
                uuidString = uuid
            } else {
                uuidString = nil
            }

            let phoneNumber: String?
            if let e164 = member.e164, !e164.isEmpty {
                phoneNumber = e164
            } else {
                phoneNumber = nil
            }

            return SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber)
        } + legacyMembers
    }
}

@objc
public extension SSKProtoGroupContext {
    var memberAddresses: [SignalServiceAddress] {
        // Parse legacy pre-uuid group members that are not represented in the members list
        let legacyMembers = membersE164.filter { e164 in members.first { $0.e164 == e164 } == nil }.map { SignalServiceAddress(phoneNumber: $0) }

        return members.map { member in
            let uuidString: String?
            if let uuid = member.uuid, !uuid.isEmpty {
                uuidString = uuid
            } else {
                uuidString = nil
            }

            let phoneNumber: String?
            if let e164 = member.e164, !e164.isEmpty {
                phoneNumber = e164
            } else {
                phoneNumber = nil
            }

            return SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber)
        } + legacyMembers
    }
}
