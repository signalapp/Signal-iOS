//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// Any view that exposes a read-only image that can be used for transitions
public protocol PrimaryImageView: UIView {
    var primaryImage: UIImage? { get }
}

extension UIImageView: PrimaryImageView {
    public var primaryImage: UIImage? { image }
}
