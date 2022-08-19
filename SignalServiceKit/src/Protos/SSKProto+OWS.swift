//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
