//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension ContactsViewHelper {
    func signalAccounts(shouldHideLocalUser: Bool) -> [SignalAccount] {
        guard shouldHideLocalUser else {
            return allSignalAccounts
        }
        let localNumber = TSAccountManager.localNumber
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
