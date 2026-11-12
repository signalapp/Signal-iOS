//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Builds `SSKProtoAttachmentPointer`s for the attachments in a single
/// outgoing envelope, including incremental MACs for at most
/// `maxIncrementalMacs` of them. Attachments are processed in the order
/// `buildProto` is called, so earlier attachments take priority.
struct IncrementalMacLimiter {
    private var remainingIncrementalMacs: Int

    init(remoteConfig: RemoteConfig) {
        self.init(
            maxIncrementalMacs: remoteConfig.maxIncrementalMacsPerEnvelope,
        )
    }

    init(maxIncrementalMacs: Int) {
        self.remainingIncrementalMacs = maxIncrementalMacs
    }

    mutating func buildProto(
        referencedAttachment: ReferencedAttachment,
    ) -> SSKProtoAttachmentPointer? {
        let proto = referencedAttachment.asProtoForSending(
            includeIncrementalMac: remainingIncrementalMacs > 0,
        )

        if let proto, proto.hasIncrementalMac {
            remainingIncrementalMacs -= 1
        }

        return proto
    }
}
