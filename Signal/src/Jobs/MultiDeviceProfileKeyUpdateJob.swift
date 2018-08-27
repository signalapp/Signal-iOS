//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMessaging

/**
 * Used to distribute our profile key to legacy linked devices, newly linked devices will have our profile key as part of provisioning.
 * Syncing is accomplished via the existing contact syncing mechanism, except the only contact synced is ourself. It's incumbent on the linked device
 * to treat this "self contact" record specially.
 */
@objc public class MultiDeviceProfileKeyUpdateJob: NSObject {

    private let profileKey: OWSAES256Key
    private let identityManager: OWSIdentityManager
    private let messageSender: MessageSender
    private let profileManager: OWSProfileManager
    private var editingDatabaseConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

   @objc public required init(profileKey: OWSAES256Key, identityManager: OWSIdentityManager, messageSender: MessageSender, profileManager: OWSProfileManager) {
        self.profileKey = profileKey

        self.identityManager = identityManager
        self.messageSender = messageSender
        self.profileManager = profileManager
    }

    @objc public class func run(profileKey: OWSAES256Key, identityManager: OWSIdentityManager, messageSender: MessageSender, profileManager: OWSProfileManager) {
        return self.init(profileKey: profileKey, identityManager: identityManager, messageSender: messageSender, profileManager: profileManager).run()
    }

    func run(retryDelay: TimeInterval = 1) {
        guard let localNumber = TSAccountManager.localNumber() else {
            owsFailDebug("localNumber was unexpectedly nil")
            return
        }

        let localSignalAccount = SignalAccount(recipientId: localNumber)
        localSignalAccount.contact = Contact()
        let syncContactsMessage = OWSSyncContactsMessage(signalAccounts: [localSignalAccount],
                                                        identityManager: self.identityManager,
                                                        profileManager: self.profileManager)

        var dataSource: DataSource?
        self.editingDatabaseConnection.readWrite { transaction in
            guard let messageData: Data = syncContactsMessage.buildPlainTextAttachmentData(with: transaction) else {
                owsFailDebug("could not serialize sync contacts data")
                return
            }
            dataSource = DataSourceValue.dataSource(withSyncMessageData: messageData)
        }

        guard let attachmentDataSource = dataSource else {
            owsFailDebug("dataSource was unexpectedly nil")
            return
        }

        self.messageSender.enqueueTemporaryAttachment(attachmentDataSource,
            contentType: OWSMimeTypeApplicationOctetStream,
            in: syncContactsMessage,
            success: {
                Logger.info("Successfully synced profile key")
            },
            failure: { error in
                Logger.error("failed with error: \(error) retrying in \(retryDelay)s.")
                after(interval: retryDelay).then {
                    self.run(retryDelay: retryDelay * 2)
                }.retainUntilComplete()
            })
    }
}
