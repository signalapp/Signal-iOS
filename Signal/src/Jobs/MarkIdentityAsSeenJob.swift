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
        switch self.thread {
        case let contactThread as TSContactThread:
            markAsSeenIfNecessary(recipientId: contactThread.contactIdentifier())
        case let groupThread as TSGroupThread:
            groupThread.groupModel.groupMemberIds?.forEach { memberId in
                guard let recipientId = memberId as? String else {
                    Logger.error("\(TAG) unexecpted type in group members.")
                    assertionFailure("\(TAG) unexecpted type in group members.")
                    return
                }

                markAsSeenIfNecessary(recipientId: recipientId)
            }
        default:
            assertionFailure("Unexpected thread type: \(self.thread)")
        }
    }

    private func markAsSeenIfNecessary(recipientId: String) {
        guard let identity = OWSRecipientIdentity.fetch(uniqueId: recipientId) else {
            Logger.verbose("\(TAG) no existing identity for recipient: \(recipientId). No messages with them yet?")
            return
        }
        if !identity.wasSeen {
            Logger.info("\(TAG) marking identity as seen for recipient: \(recipientId)")
            identity.markAsSeen()
            identity.save()
        }
    }
}
