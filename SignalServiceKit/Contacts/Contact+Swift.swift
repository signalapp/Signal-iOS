//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension Contact {
    func discoverableRecipients(tx: SDSAnyReadTransaction) -> [SignalRecipient] {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        return e164sForIntersection.compactMap { phoneNumber in
            let recipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber, transaction: tx.asV2Read)
            guard let recipient, recipient.isPhoneNumberDiscoverable else {
                return nil
            }
            return recipient
        }
    }

    var e164sForIntersection: [String] {
        var phoneNumbers: OrderedSet<String> = []

        for phoneNumber in parsedPhoneNumbers {
            let phoneNumberE164 = phoneNumber.toE164()
            phoneNumbers.append(phoneNumberE164)

            if phoneNumberE164.hasPrefix("+52") {
                if phoneNumberE164.hasPrefix("+521") {
                    let withoutMobilePrefix = phoneNumberE164.replacingOccurrences(of: "+521", with: "+52")
                    phoneNumbers.append(withoutMobilePrefix)
                } else {
                    let withMobilePrefix = phoneNumberE164.replacingOccurrences(of: "+52", with: "+521")
                    phoneNumbers.append(withMobilePrefix)
                }
            }
        }

        return phoneNumbers.orderedMembers
    }
}
