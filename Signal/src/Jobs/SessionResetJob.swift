//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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

        OWSDispatch.sessionStoreQueue().async {
            Logger.info("\(self.TAG) deleting sessions for recipient: \(self.recipientId)")
            self.storageManager.deleteAllSessions(forContact: self.recipientId)

            DispatchQueue.main.async {
                let endSessionMessage = EndSessionMessage(timestamp:NSDate.ows_millisecondTimeStamp(), in: self.thread)

                self.messageSender.send(endSessionMessage, success: {
                    Logger.info("\(self.TAG) successfully sent EndSession<essage.")
                    let message = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(),
                                                in: self.thread,
                                                messageType: TSInfoMessageType.typeSessionDidEnd)
                    message.save()
                }, failure: {error in
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
