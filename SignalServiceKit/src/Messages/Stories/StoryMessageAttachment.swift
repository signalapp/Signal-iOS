//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct StoryMessageFileAttachment: Codable {
    public let attachmentId: String
    public let captionStyles: [NSRangedValue<MessageBodyRanges.CollapsedStyle>]

    public init(
        attachmentId: String,
        storyBodyRangeProtos: [SSKProtoBodyRange]
    ) {
        let bodyRanges = MessageBodyRanges(protos: storyBodyRangeProtos)
        // Drop mentions, don't even hydrate them.
        self.init(attachmentId: attachmentId, captionStyles: bodyRanges.collapsedStyles)
    }

    public init(attachmentId: String, captionStyles: [NSRangedValue<MessageBodyRanges.CollapsedStyle>]) {
        self.attachmentId = attachmentId
        self.captionStyles = captionStyles
    }

    public func captionProtoBodyRanges() -> [SSKProtoBodyRange] {
        return MessageBodyRanges(mentions: [:], orderedMentions: [], collapsedStyles: captionStyles).toProtoBodyRanges()
    }

    public enum CodingKeys: String, CodingKey {
        case attachmentId
        case captionStyles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.attachmentId = try container.decode(String.self, forKey: .attachmentId)

        // Backwards compability; this used to contain NSRangedValue<Style>,
        // but now contains NSRangedValue<CollapsedStyle>
        if let rawStyles = try? container.decodeIfPresent([NSRangedValue<MessageBodyRanges.Style>].self, forKey: .captionStyles) {
            // Re-process the styles in order to collapse them.
            let singleStyles = rawStyles.flatMap { style in
                return style.value.contents.map {
                    return NSRangedValue($0, range: style.range)
                }
            }
            let messageBodyRanges = MessageBodyRanges(mentions: [:], styles: singleStyles)
            self.captionStyles = messageBodyRanges.collapsedStyles
        } else {
            self.captionStyles = try container.decode([NSRangedValue<MessageBodyRanges.CollapsedStyle>].self, forKey: .captionStyles)
        }
    }
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
    case fileV2(StoryMessageFileAttachment)

    var asPublicAttachment: StoryMessageAttachment {
        switch self {
        case .file(let attachmentId):
            return .file(StoryMessageFileAttachment(attachmentId: attachmentId, captionStyles: []))
        case .fileV2(let storyMessageFileAttachment):
            return .file(storyMessageFileAttachment)
        case .text(let attachment):
            return .text(attachment)
        }
    }
}

public enum StoryMessageAttachment {
    case file(StoryMessageFileAttachment)
    case text(TextAttachment)

    internal var asSerializable: SerializedStoryMessageAttachment {
        switch self {
        case .file(let storyMessageFileAttachment):
            return .fileV2(storyMessageFileAttachment)
        case .text(let textAttachment):
            return .text(attachment: textAttachment)
        }
    }
}
