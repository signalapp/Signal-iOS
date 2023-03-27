//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import UIKit
import SignalUI

final class UIStackViewExtensionsTest: XCTestCase {
    func testRemoveArrangedSubviewsAfter() {
        let a = UIView()
        let b = UIView()
        let c = UIView()
        let d = UIView()

        let stack = UIStackView(arrangedSubviews: [a, b, c])

        stack.removeArrangedSubviewsAfter(d)
        XCTAssertEqual(stack.arrangedSubviews, [a, b, c])

        stack.removeArrangedSubviewsAfter(c)
        XCTAssertEqual(stack.arrangedSubviews, [a, b, c])

        stack.removeArrangedSubviewsAfter(b)
        XCTAssertEqual(stack.arrangedSubviews, [a, b])

        stack.removeArrangedSubviewsAfter(a)
        XCTAssertEqual(stack.arrangedSubviews, [a])
    }
}
