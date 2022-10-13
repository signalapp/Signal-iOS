//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension SSKProtoGroupDetails {
    var memberAddresses: [SignalServiceAddress] {
        return membersE164.map { SignalServiceAddress(phoneNumber: $0) }
    }
}

@objc
public extension SSKProtoGroupContext {
    var memberAddresses: [SignalServiceAddress] {
        return membersE164.map { SignalServiceAddress(phoneNumber: $0) }
    }
}

@objc
public extension SSKProtoSyncMessageSent {
    var isStoryTranscript: Bool {
        storyMessage != nil || !storyMessageRecipients.isEmpty
    }
}
