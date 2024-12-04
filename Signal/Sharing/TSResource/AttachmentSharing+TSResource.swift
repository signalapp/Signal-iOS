//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public enum ShareableTSResource {
    case v2(ShareableAttachment)
}

extension AttachmentSharing {

    public static func showShareUI(
        for attachment: ShareableTSResource,
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        showShareUI(for: [attachment], sender: sender, completion: completion)
    }

    public static func showShareUI(
        for attachments: [ShareableTSResource],
        sender: Any? = nil,
        completion: (() -> Void)? = nil
    ) {
        var streams = [ShareableAttachment]()
        attachments.forEach { attachment in
            switch attachment {
            case .v2(let attachment):
                streams.append(attachment)
            }
        }

        if streams.isEmpty.negated {
            showShareUI(for: streams, sender: sender, completion: completion)
        }
    }
}

extension ReferencedTSResourceStream {

    public func asShareableResource() throws -> ShareableTSResource? {
        return try self.attachmentStream.asShareableResource(sourceFilename: reference.sourceFilename)
    }
}

extension AttachmentStream {

    public func asShareableResource(sourceFilename: String?) throws -> ShareableTSResource? {
        return try self.asShareableAttachment(sourceFilename: sourceFilename).map { .v2($0) }
    }
}
