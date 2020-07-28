//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objcMembers
public class MessageBody: NSObject, NSSecureCoding {
    public static var supportsSecureCoding = true
    public static let mentionPlaceholder = "\u{FFFC}" // Object Replacement Character

    public let text: String
    public let mentionRanges: [NSRange: UUID]

    public var hasMentions: Bool { !mentionRanges.isEmpty }

    public init(text: String, mentionRanges: [NSRange: UUID]) {
        self.text = text
        self.mentionRanges = mentionRanges

        super.init()
    }

    public required init?(coder: NSCoder) {
        let mentionRangesCount = coder.decodeInteger(forKey: "mentionRangesCount")

        var mentionRanges = [NSRange: UUID]()
        for idx in 0..<mentionRangesCount {
            guard let range = coder.decodeObject(of: NSValue.self, forKey: "mentionRanges.key.\(idx)")?.rangeValue else {
                owsFailDebug("Failed to decode mention range key of MessageBody")
                return nil
            }
            guard let uuid = coder.decodeObject(of: NSUUID.self, forKey: "mentionRanges.value.\(idx)") as UUID? else {
                owsFailDebug("Failed to decode mention range value of MessageBody")
                return nil
            }
            mentionRanges[range] = uuid
        }

        guard let text = coder.decodeObject(of: NSString.self, forKey: "text") as String? else {
            owsFailDebug("Failed to decode text MessageBody")
            return nil
        }

        self.mentionRanges = mentionRanges
        self.text = text
    }

    public func encode(with coder: NSCoder) {
        coder.encode(text as NSString, forKey: "text")
        coder.encode(mentionRanges.count, forKey: "mentionRangesCount")
        for (idx, (range, uuid)) in mentionRanges.enumerated() {
            coder.encode(NSValue(range: range), forKey: "mentionRanges.key.\(idx)")
            coder.encode(uuid, forKey: "mentionRanges.value.\(idx)")
        }
    }
}
