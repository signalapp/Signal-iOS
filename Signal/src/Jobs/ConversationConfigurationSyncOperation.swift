//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ConversationConfigurationSyncOperation: OWSOperation {

    enum ColorSyncOperationError: Error {
        case assertionError(description: String)
    }

    private var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadConnection
    }

    private var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var syncManager: OWSSyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
    }

    private let thread: TSThread

    @objc
    public init(thread: TSThread) {
        self.thread = thread
        super.init()
    }

    override public func run() {
        if let contactThread = thread as? TSContactThread {
            sync(contactThread: contactThread)
        } else if let groupThread = thread as? TSGroupThread {
            sync(groupThread: groupThread)
        } else {
            self.reportAssertionError(description: "unknown thread type")
        }
    }

    private func reportAssertionError(description: String) {
        let error = ColorSyncOperationError.assertionError(description: description)
        self.reportError(error)
    }

    private func sync(contactThread: TSContactThread) {
        guard let signalAccount: SignalAccount = self.contactsManager.fetchSignalAccount(for: contactThread.contactAddress) else {
            reportAssertionError(description: "unable to find signalAccount")
            return
        }

        syncManager.syncContacts(for: [signalAccount]).retainUntilComplete()
    }

    private func sync(groupThread: TSGroupThread) {
        // TODO sync only the affected group
        // The current implementation works, but seems wasteful.
        // Does desktop handle single group sync correctly?
        // What does Android do?
        let syncMessage: OWSSyncGroupsMessage = OWSSyncGroupsMessage()

        var dataSource: DataSource?
        self.dbConnection.read { transaction in
            guard let messageData: Data = syncMessage.buildPlainTextAttachmentData(with: transaction) else {
                owsFailDebug("could not serialize sync groups data")
                return
            }
            dataSource = DataSourceValue.dataSource(withSyncMessageData: messageData)
        }

        guard let attachmentDataSource = dataSource else {
            self.reportAssertionError(description: "unable to build attachment data source")
            return
        }

        self.sendConfiguration(attachmentDataSource: attachmentDataSource, syncMessage: syncMessage)
    }

    private func sendConfiguration(attachmentDataSource: DataSource, syncMessage: OWSOutgoingSyncMessage) {
        self.messageSenderJobQueue.add(mediaMessage: syncMessage,
                                       dataSource: attachmentDataSource,
                                       contentType: OWSMimeTypeApplicationOctetStream,
                                       sourceFilename: nil,
                                       caption: nil,
                                       albumMessageId: nil,
                                       isTemporaryAttachment: true)
        self.reportSuccess()
    }

}
