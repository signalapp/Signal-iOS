//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if USE_DEBUG_UI

@objc
public extension DebugContactsUtils {

    static func reindexAllContacts() {
        databaseStorage.write { transaction in
            SignalAccount.anyEnumerate(transaction: transaction, batched: true) { (account: SignalAccount, _) in
                account.anyUpsert(transaction: transaction)
            }
            SignalRecipient.anyEnumerate(transaction: transaction, batched: true) { (signalRecipient: SignalRecipient, _) in
                signalRecipient.anyUpsert(transaction: transaction)
            }
            TSThread.anyEnumerate(transaction: transaction, batched: true) { (thread: TSThread, _) in
                databaseStorage.touch(thread: thread, shouldReindex: true, transaction: transaction)
            }
        }
    }

    static func logSignalAccounts() {
        databaseStorage.read { transaction in
            SignalAccount.anyEnumerate(transaction: transaction, batched: true) { (account: SignalAccount, _) in
                Logger.verbose("---- \(account.uniqueId),  \(account.recipientAddress),  \(String(describing: account.contactFirstName())),  \(String(describing: account.contactLastName())),  \(String(describing: account.contactNicknameIfAvailable())), ")
            }
        }
    }
}

#endif
