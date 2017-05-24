//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class MarkIdentityAsSeenJob: NSObject {
    let TAG = "[MarkIdentityAsSeenJob]"

    private let thread: TSThread

    public class func run(thread: TSThread) {
        MarkIdentityAsSeenJob(thread: thread).run()
    }

    init(thread: TSThread) {
        self.thread = thread
    }

    public func run() {
        for recipientId in self.thread.recipientIdentifiers {
            markAsSeenIfNecessary(recipientId: recipientId)
        }
    }

    private func markAsSeenIfNecessary(recipientId: String) {
        guard let identity = OWSRecipientIdentity.fetch(uniqueId: recipientId) else {
            Logger.verbose("\(self.TAG) no existing identity for recipient: \(recipientId). No messages with them yet?")
            return
        }
        if !identity.wasSeen {
            Logger.info("\(self.TAG) marking identity as seen for recipient: \(recipientId)")
            identity.updateAsSeen()
        }
    }
}
