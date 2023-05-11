//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if USE_DEBUG_UI

@objc
public extension DebugContactsUtils {

    static func logSignalAccounts() {
        databaseStorage.read { transaction in
            SignalAccount.anyEnumerate(transaction: transaction, batchingPreference: .batched()) { (account: SignalAccount, _) in
                Logger.verbose("---- \(account.uniqueId),  \(account.recipientAddress),  \(String(describing: account.contactFirstName)),  \(String(describing: account.contactLastName)),  \(String(describing: account.contactNicknameIfAvailable())), ")
            }
        }
    }
}

#endif
