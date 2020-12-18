//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension Contact {

    func signalRecipients(transaction: SDSAnyReadTransaction) -> [SignalRecipient] {
        e164sForIntersection.compactMap { e164Number in
            let address = SignalServiceAddress(phoneNumber: e164Number)
            return SignalRecipient.get(address: address, mustHaveDevices: true, transaction: transaction)
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
