//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit

@objc(OWSNewAccountDiscovery)
public class NewAccountDiscovery: NSObject {

    @objc
    public static let shared = NewAccountDiscovery()

    // MARK: -

    @objc(discoveredNewRecipients:)
    public func discovered(newRecipients: Set<SignalRecipient>) {
        discovered(newRecipients: newRecipients, forNewThreadsOnly: true)
    }

    public func discovered(newRecipients: Set<SignalRecipient>, forNewThreadsOnly: Bool) {
        let shouldNotifyOfNewAccounts = databaseStorage.read { transaction in
            self.preferences.shouldNotifyOfNewAccounts(transaction: transaction)
        }

        guard shouldNotifyOfNewAccounts else {
            Logger.verbose("not notifying due to preferences.")
            return
        }

        databaseStorage.asyncWrite { transaction in
            for recipient in newRecipients {

                guard !recipient.address.isLocalAddress else {
                    owsFailDebug("unexpectedly found localNumber")
                    continue
                }

                // Typically we'd never want to create a "new user" notification if the thread already existed
                // but for testing we disabled the `forNewThreadsOnly` flag.
                if forNewThreadsOnly {
                    guard TSContactThread.getWithContactAddress(recipient.address, transaction: transaction) == nil else {
                        Logger.info("not creating notification for reregistered user with existing thread.")
                        continue
                    }
                }

                let thread = TSContactThread.getOrCreateThread(withContactAddress: recipient.address, transaction: transaction)
                let message = TSInfoMessage(thread: thread,
                                            messageType: .userJoinedSignal)
                message.anyInsert(transaction: transaction)

                guard let notificationPresenter = Self.notificationPresenter else {
                    owsFailDebug("Missing notificationPresenter.")
                    continue
                }

                // Keep these notifications less obtrusive by making them silent.
                notificationPresenter.notifyUser(
                    forTSMessage: message,
                    thread: thread,
                    wantsSound: false,
                    transaction: transaction
                )
            }
        }
    }
}
