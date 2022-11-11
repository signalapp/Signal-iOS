//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

    func registeredAddresses() -> [SignalServiceAddress] {
        databaseStorage.read { transaction in
            registeredAddresses(transaction: transaction)
        }
    }

    func registeredAddresses(transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        e164sForIntersection.compactMap { e164 in
            let address = SignalServiceAddress(phoneNumber: e164)
            if SignalRecipient.isRegisteredRecipient(address, transaction: transaction) {
                return address
            } else {
                return nil
            }
        }
    }
}
