//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import CoreFoundation

public extension UIButton {
    /// Add spacing between a button's image and its title.
    ///
    /// Modified from [this project][0], licensed under the MIT License.
    ///
    /// [0]: https://github.com/noahsark769/NGUIButtonInsetsExample
    func setPaddingBetweenImageAndText(to padding: CGFloat, isRightToLeft: Bool) {
        if isRightToLeft {
            contentEdgeInsets = .init(
                top: contentEdgeInsets.top,
                left: padding,
                bottom: contentEdgeInsets.bottom,
                right: contentEdgeInsets.right
            )
            titleEdgeInsets = .init(
                top: titleEdgeInsets.top,
                left: -padding,
                bottom: titleEdgeInsets.bottom,
                right: padding
            )
        } else {
            contentEdgeInsets = .init(
                top: contentEdgeInsets.top,
                left: contentEdgeInsets.left,
                bottom: contentEdgeInsets.bottom,
                right: padding
            )
            titleEdgeInsets = .init(
                top: titleEdgeInsets.top,
                left: padding,
                bottom: titleEdgeInsets.bottom,
                right: -padding
            )
        }
    }
}
