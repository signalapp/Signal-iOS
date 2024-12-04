//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

internal struct Deprecated_StoryMessageFileAttachment: Codable {

    private init() {}
}

/// Exists for backwards compatibility, and used whenever we want to read/write
/// a StoryMessageAttachment to disk.
/// Codable conformance for enums with associated values is messy and error prone;
/// this allows us to take advantage of automatic synthesis by preserving cases
/// exactly as they were defined, and only every adding new cases.
internal enum SerializedStoryMessageAttachment: Codable {
    // Original case. NEVER CHANGE THIS.
    case file(attachmentId: String)
    // Original case. NEVER CHANGE THIS.
    case text(attachment: TextAttachment)

    // V2 case. Same as file, but with added body ranges.
    // original file case assumed to have empty body ranges
    // but is otherwise perfectly convertible once decoded.
    case fileV2(Deprecated_StoryMessageFileAttachment)

    /// The attachment reference can be found in a separate join table.
    case foreignReferenceAttachment

    var asPublicAttachment: StoryMessageAttachment {
        switch self {
        case .file, .fileV2, .foreignReferenceAttachment:
            return .media
        case .text(let attachment):
            return .text(attachment)
        }
    }
}

public enum StoryMessageAttachment {
    /// The attachment reference can be found in a separate join table.
    case media
    case text(TextAttachment)

    internal var asSerializable: SerializedStoryMessageAttachment {
        switch self {
        case .media:
            return .foreignReferenceAttachment
        case .text(let textAttachment):
            return .text(attachment: textAttachment)
        }
    }
}
