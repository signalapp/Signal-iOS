//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension ContactsViewHelper {
    @objc(signalAccountsIncludingLocalUser:)
    func signalAccounts(includingLocalUser: Bool) -> [SignalAccount] {
        guard !includingLocalUser else {
            return allSignalAccounts
        }
        guard let localNumber = TSAccountManager.localNumber else {
            return allSignalAccounts
        }
        return allSignalAccounts.filter { signalAccount in
            if signalAccount.recipientAddress.isLocalAddress {
                return false
            }
            if let contact = signalAccount.contact {
                for phoneNumber in contact.parsedPhoneNumbers {
                    if phoneNumber.toE164() == localNumber {
                        return false
                    }
                }
            }
            return true
        }
    }
}
