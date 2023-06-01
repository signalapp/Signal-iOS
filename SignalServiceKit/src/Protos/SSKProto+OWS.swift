//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension SSKProtoSyncMessageSent {
    var isStoryTranscript: Bool {
        storyMessage != nil || !storyMessageRecipients.isEmpty
    }
}

public extension SSKProtoEnvelope {
    var sourceServiceId: ServiceId? {
        ServiceId(uuidString: sourceUuid)
    }

    @objc
    var sourceServiceIdObjC: ServiceIdObjC? {
        sourceServiceId.map { ServiceIdObjC($0) }
    }
}
