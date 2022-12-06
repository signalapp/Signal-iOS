//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public extension UIEdgeInsets {

    func inverted() -> UIEdgeInsets {
        return UIEdgeInsets(top: -top, left: -left, bottom: -bottom, right: -right)
    }
}

public extension CGSize {

    func roundedForScreenScale() -> CGSize {
        let screenScale = UIScreen.main.scale
        guard screenScale > 1 else { return self }
        return CGSize(
            width: (width * screenScale).rounded(.up) / screenScale,
            height: (height * screenScale).rounded(.up) / screenScale
        )
    }
}
