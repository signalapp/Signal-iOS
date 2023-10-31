//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension Contact {

    func signalRecipients(tx: SDSAnyReadTransaction) -> [SignalRecipient] {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        return e164sForIntersection.compactMap { e164Number in
            guard let recipient = recipientDatabaseTable.fetchRecipient(phoneNumber: e164Number, transaction: tx.asV2Read) else {
                return nil
            }
            guard recipient.isRegistered else {
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

    func registeredAddresses() -> [SignalServiceAddress] {
        databaseStorage.read { transaction in
            registeredAddresses(transaction: transaction)
        }
    }

    func registeredAddresses(transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        e164sForIntersection.compactMap { e164 in
            let address = SignalServiceAddress(phoneNumber: e164)
            if SignalRecipient.isRegistered(address: address, tx: transaction) {
                return address
            } else {
                return nil
            }
        }
    }
}
