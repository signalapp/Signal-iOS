//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

@objc(OWSSessionResetJob)
class SessionResetJob: NSObject {

    let TAG = "SessionResetJob"

    let recipientId: String
    let thread: TSThread
    let storageManager: TSStorageManager
    let messageSender: MessageSender

    required init(recipientId: String, thread: TSThread, messageSender: MessageSender, storageManager: TSStorageManager) {
        self.thread = thread
        self.recipientId = recipientId
        self.messageSender = messageSender
        self.storageManager = storageManager
    }

    func run() {
        Logger.info("\(TAG) Local user reset session.")

        TSStorageManager.protocolStoreDBConnection().asyncReadWrite { (transaction) in
            Logger.info("\(self.TAG) deleting sessions for recipient: \(self.recipientId)")
            self.storageManager.deleteAllSessions(forContact: self.recipientId, protocolContext: transaction)

            DispatchQueue.main.async {
                let endSessionMessage = EndSessionMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: self.thread)

                self.messageSender.enqueue(endSessionMessage, success: {
                    TSStorageManager.protocolStoreDBConnection().asyncReadWrite { (transaction) in
                        // Archive the just-created session since the recipient should delete their corresponding
                        // session upon receiving and decrypting our EndSession message.
                        // Otherwise if we send another message before them, they wont have the session to decrypt it.
                        self.storageManager.archiveAllSessions(forContact: self.recipientId, protocolContext: transaction)
                    }
                    Logger.info("\(self.TAG) successfully sent EndSessionMessage.")
                    let message = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(),
                                                in: self.thread,
                                                messageType: TSInfoMessageType.typeSessionDidEnd)
                    message.save()
                }, failure: {error in
                    TSStorageManager.protocolStoreDBConnection().asyncReadWrite { (transaction) in
                        // Even though this is the error handler - which means probably the recipient didn't receive the message
                        // there's a chance that our send did succeed and the server just timed out our repsonse or something.
                        // Since the cost of sending a future message using a session the recipient doesn't have is so high,
                        // we archive the session just in case.
                        //
                        // Archive the just-created session since the recipient should delete their corresponding
                        // session upon receiving and decrypting our EndSession message.
                        // Otherwise if we send another message before them, they wont have the session to decrypt it.
                        self.storageManager.archiveAllSessions(forContact: self.recipientId, protocolContext: transaction)
                    }
                    Logger.error("\(self.TAG) failed to send EndSessionMessage with error: \(error.localizedDescription)")
                })
            }
        }
    }

    class func run(contactThread: TSContactThread, messageSender: MessageSender, storageManager: TSStorageManager) {
        let job = self.init(recipientId: contactThread.contactIdentifier(),
                            thread: contactThread,
                            messageSender: messageSender,
                            storageManager: storageManager)
        job.run()
    }
}
