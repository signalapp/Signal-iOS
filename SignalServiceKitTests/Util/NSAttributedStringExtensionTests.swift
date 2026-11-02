//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import SignalServiceKit

struct NSAttributedStringExtensionTests {
    @Test
    func testAttributeAvoidingSubrange() {
        var mutableString = NSMutableAttributedString(string: "🐝 kind to all kinds")
        let attributes = [NSAttributedString.Key.foregroundColor: UIColor.yellow]

        var subrangeToAvoid = (mutableString.string as NSString).range(of: "all")

        mutableString.applyAttributesToRangeAvoidingSubrange(
            attributes: attributes,
            range: mutableString.entireRange,
            subrangeToAvoid: subrangeToAvoid,
        )

        mutableString.enumerateAttributes(in: mutableString.entireRange, options: []) { attrs, subrange, _ in
            if NSIntersectionRange(subrange, subrangeToAvoid).length > 0 {
                #expect(attrs.isEmpty)
            } else {
                #expect(attrs[NSAttributedString.Key.foregroundColor] as! NSObject == UIColor.yellow)
            }
        }

        // subrange not intersecting range.
        mutableString = NSMutableAttributedString(string: "🐝 kind to all kinds")
        subrangeToAvoid = NSRange(location: 25, length: 1)

        mutableString.applyAttributesToRangeAvoidingSubrange(
            attributes: attributes,
            range: mutableString.entireRange,
            subrangeToAvoid: subrangeToAvoid,
        )

        mutableString.enumerateAttributes(in: mutableString.entireRange, options: []) { attrs, subrange, _ in
            #expect(attrs[NSAttributedString.Key.foregroundColor] as! NSObject == UIColor.yellow, "Entire string should have attribute")
        }

        // subrange with partial intersection
        mutableString = NSMutableAttributedString(string: "🐝 kind to all kinds")
        subrangeToAvoid = NSRange(location: 18, length: 10)

        mutableString.applyAttributesToRangeAvoidingSubrange(
            attributes: attributes,
            range: mutableString.entireRange,
            subrangeToAvoid: subrangeToAvoid,
        )

        mutableString.enumerateAttributes(in: mutableString.entireRange, options: []) { attrs, subrange, _ in
            if NSIntersectionRange(subrange, subrangeToAvoid).length > 0 {
                #expect(attrs.isEmpty)
            } else {
                #expect(attrs[NSAttributedString.Key.foregroundColor] as! NSObject == UIColor.yellow)
            }
        }
    }
}
