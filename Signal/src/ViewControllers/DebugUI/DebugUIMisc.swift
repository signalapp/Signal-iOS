//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import MobileCoin
import SignalServiceKit

#if DEBUG

@objc
public extension DebugUIMisc {
    static func logLocalAccount() {
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return
        }
        if let uuid = localAddress.uuid {
            Logger.verbose("localAddress uuid: \(uuid)")
        }
        if let phoneNumber = localAddress.phoneNumber {
            Logger.verbose("localAddress phoneNumber: \(phoneNumber)")
        }
    }

    static func logSignalRecipients() {
        Self.databaseStorage.read { transaction in
            SignalRecipient.anyEnumerate(transaction: transaction, batchSize: 32) { (signalRecipient, _) in
                Logger.verbose("SignalRecipient: \(signalRecipient.addressComponentsDescription)")
            }
        }
    }

    static func logSignalAccounts() {
        Self.databaseStorage.read { transaction in
            SignalAccount.anyEnumerate(transaction: transaction, batchSize: 32) { (signalAccount, _) in
                Logger.verbose("SignalAccount: \(signalAccount.addressComponentsDescription)")
            }
        }
    }

    static func logContactThreads() {
        Self.databaseStorage.read { transaction in
            TSContactThread.anyEnumerate(transaction: transaction, batchSize: 32) { (thread, _) in
                guard let thread = thread as? TSContactThread else {
                    return
                }
                Logger.verbose("TSContactThread: \(thread.addressComponentsDescription)")
            }
        }
    }

    static func clearProfileKeyCredentials() {
        Self.databaseStorage.write { transaction in
            Self.versionedProfiles.clearProfileKeyCredentials(transaction: transaction)
        }
    }

    static func clearTemporalCredentials() {
        Self.databaseStorage.write { transaction in
            Self.groupsV2.clearTemporalCredentials(transaction: transaction)
        }
    }

    static func clearLocalCustomEmoji() {
        Self.databaseStorage.write { transaction in
            ReactionManager.setCustomEmojiSet(nil, transaction: transaction)
        }
    }
}

#endif
