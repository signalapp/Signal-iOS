//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SSKJobQueues: NSObject {
    public override init() {
        messageSenderJobQueue = MessageSenderJobQueue()

        localUserLeaveGroupJobQueue = LocalUserLeaveGroupJobQueue()
    }

    // MARK: @objc

    @objc
    public let messageSenderJobQueue: MessageSenderJobQueue

    // MARK: Swift-only

    public let localUserLeaveGroupJobQueue: LocalUserLeaveGroupJobQueue
}
