//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension Attachment {
    /// How long we keep attachment files locally by default when "optimize local storage"
    /// is enabled. Measured from the receive time of the most recent owning message.
    public static let offloadingThresholdMs: UInt64 = .dayInMs * 30

    /// How long we keep attachment files locally after viewing them when "optimize local storage"
    /// is enabled.
    private static let offloadingViewThresholdMs: UInt64 = .dayInMs

    /// Returns true if the given attachment should be offloaded (have its local file(s) deleted)
    /// because it has met the criteria to be stored exclusively in the backup media tier.
    public func shouldBeOffloaded(
        shouldOptimizeLocalStorage: Bool,
        currentUploadEra: String,
        currentTimestamp: UInt64,
        attachmentStore: AttachmentStore,
        tx: DBReadTransaction
    ) throws -> Bool {
        guard shouldOptimizeLocalStorage else {
            // Don't offload anything unless this setting is enabled.
            return false
        }
        guard let stream = self.asStream() else {
            // We only offload stuff we have locally, duh.
            return false
        }
        if stream.needsMediaTierUpload(currentUploadEra: currentUploadEra) {
            // Don't offload until we've backed up to media tier.
            return false
        }
        if
            let viewedTimestamp = self.lastFullscreenViewTimestamp,
            viewedTimestamp + Self.offloadingViewThresholdMs > currentTimestamp
        {
            // Don't offload if viewed recently.
            return false
        }

        // Lastly find the most recent owner and use its timestamp to determine
        // eligibility to offload.
        switch try attachmentStore.fetchMostRecentReference(toAttachmentId: self.id, tx: tx).owner {
        case .message(let messageSource):
            return messageSource.receivedAtTimestamp + Self.offloadingThresholdMs > currentTimestamp
        case .storyMessage:
            // Story messages expire on their own; never offload
            // any attachment owned by a story message.
            return false
        case .thread:
            // We never offload thread wallpapers.
            return false
        }
    }
}

extension AttachmentStore {

    func fetchMostRecentReference(
        toAttachmentId attachmentId: Attachment.IDType,
        tx: DBReadTransaction
    ) throws -> AttachmentReference {
        var mostRecentReference: AttachmentReference?
        var maxMessageTimestamp: UInt64 = 0
        try self.enumerateAllReferences(
            toAttachmentId: attachmentId,
            tx: tx
        ) { reference, stop in
            switch reference.owner {
            case .message(let messageSource):
                switch mostRecentReference?.owner {
                case nil, .message:
                    if messageSource.receivedAtTimestamp > maxMessageTimestamp {
                        maxMessageTimestamp = messageSource.receivedAtTimestamp
                        mostRecentReference = reference
                    }
                case .storyMessage, .thread:
                    // Always consider these more "recent" than messages.
                    break
                }
            case .storyMessage:
                switch mostRecentReference?.owner {
                case nil, .message, .storyMessage:
                    mostRecentReference = reference
                case .thread:
                    // Always consider these more "recent" than story messages.
                    break
                }

            case .thread:
                // We always treat wallpapers as "most recent".
                stop = true
                mostRecentReference = reference
            }
        }
        guard let mostRecentReference else {
            throw OWSAssertionError("Attachment without an owner! Was the attachment deleted?")
        }
        return mostRecentReference
    }
}
