//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objcMembers
public class MentionText: NSObject, NSSecureCoding {
    public static var supportsSecureCoding = true

    public let text: String
    public let ranges: [MentionRange]

    public init(text: String, ranges: [MentionRange]) {
        self.text = text
        self.ranges = ranges

        super.init()
    }

    public required init?(coder: NSCoder) {
        let rangesCount = coder.decodeInteger(forKey: "rangesCount")

        var ranges = [MentionRange]()
        for idx in 0..<rangesCount {
            guard let range = coder.decodeObject(of: MentionRange.self, forKey: "ranges.\(idx)") else {
                owsFailDebug("Failed to decode ranges of MentionText")
                return nil
            }
            ranges.append(range)
        }

        guard let text = coder.decodeObject(of: NSString.self, forKey: "text") as String? else {
            owsFailDebug("Failed to decode MentionText")
            return nil
        }

        self.ranges = ranges
        self.text = text
    }

    public func encode(with coder: NSCoder) {
        coder.encode(text as NSString, forKey: "text")
        coder.encode(ranges.count, forKey: "rangesCount")
        for (idx, range) in ranges.enumerated() {
            coder.encode(range, forKey: "ranges.\(idx)")
        }
    }
}
