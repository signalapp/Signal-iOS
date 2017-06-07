//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class MarkIdentityAsSeenJob: NSObject {
    let TAG = "[MarkIdentityAsSeenJob]"

    private let recipientIds: [String]

    public class func run(thread: TSThread) {
        let recipientIds = thread.recipientIdentifiers

        MarkIdentityAsSeenJob(recipientIds: recipientIds).run()
    }

    public class func run(recipientId: String) {
        MarkIdentityAsSeenJob(recipientIds: [recipientId]).run()
    }

    init(recipientIds: [String]) {
        self.recipientIds = recipientIds
    }

    public func run() {
        for recipientId in self.recipientIds {
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
