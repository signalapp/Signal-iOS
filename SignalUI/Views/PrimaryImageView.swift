//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Any view that exposes a read-only image that can be used for transitions
public protocol PrimaryImageView: UIView {
    var primaryImage: UIImage? { get }
}

extension UIImageView: PrimaryImageView {
    public var primaryImage: UIImage? { image }
}
