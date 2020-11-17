//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UIGestureRecognizer {
    @objc
    public var stateString: String {
        return NSStringForUIGestureRecognizerState(state)
    }
}
