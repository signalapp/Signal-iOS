//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
public extension SSKProtoSyncMessageSent {
    var isStoryTranscript: Bool {
        storyMessage != nil || !storyMessageRecipients.isEmpty
    }
}
