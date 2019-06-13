//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSNewAccountDiscovery)
public class NewAccountDiscovery: NSObject {

    @objc
    public static let shared = NewAccountDiscovery()

    // MARK: - Dependencies

    var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    var notificationPresenter: NotificationsProtocol {
        return SSKEnvironment.shared.notificationsManager
    }

    // MARK: -

    @objc(discoveredNewRecipients:)
    public func discovered(newRecipients: Set<SignalRecipient>) {
        discovered(newRecipients: newRecipients, forNewThreadsOnly: true)
    }

    public func discovered(newRecipients: Set<SignalRecipient>, forNewThreadsOnly: Bool) {
        let shouldNotifyOfNewAccounts = databaseStorage.readReturningResult { transaction in
            self.preferences.shouldNotifyOfNewAccounts(transaction: transaction)
        }

        guard shouldNotifyOfNewAccounts else {
            Logger.verbose("not notifying due to preferences.")
            return
        }

        let localNumber = TSAccountManager.localNumber()
        databaseStorage.asyncWrite { transaction in
            // Don't spam inbox with a ton of these
            for recipient in newRecipients.prefix(3) {

                guard recipient.recipientId != localNumber else {
                    owsFailDebug("unexpectedly found localNumber")
                    continue
                }

                // Typically we'd never want to create a "new user" notification if the thread already existed
                // but for testing we disabled the `forNewThreadsOnly` flag.
                if forNewThreadsOnly {
                    guard TSContactThread.getWithContactId(recipient.recipientId, anyTransaction: transaction) == nil else {
                        owsFailDebug("not creating notification for 'new' user in existing thread.")
                        continue
                    }
                }

                let thread = TSContactThread.getOrCreateThread(withContactId: recipient.recipientId, anyTransaction: transaction)
                let message = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(),
                                            in: thread,
                                            messageType: .userJoinedSignal)
                message.anyInsert(transaction: transaction)

                guard isReasonableTimeToNotify() else {
                    Logger.info("Skipping notification due to time of day")
                    return
                }

                self.notificationPresenter.notifyUser(for: message, thread: thread, transaction: transaction)
            }
        }

        func isReasonableTimeToNotify() -> Bool {
            let hour = Calendar.current.component(.hour, from: Date())

            return (9..<23).contains(hour)
        }
    }
}
