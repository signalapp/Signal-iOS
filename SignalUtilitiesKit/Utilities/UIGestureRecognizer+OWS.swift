//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

extension UIGestureRecognizer {
    @objc
    public var stateString: String {
        return state.asString
    }
}

extension UIGestureRecognizer.State {
    fileprivate var asString: String {
        switch self {
            case .possible: return "UIGestureRecognizerStatePossible"
            case .began: return "UIGestureRecognizerStateBegan"
            case .changed: return "UIGestureRecognizerStateChanged"
            case .ended: return "UIGestureRecognizerStateEnded"
            case .cancelled: return "UIGestureRecognizerStateCancelled"
            case .failed: return "UIGestureRecognizerStateFailed"
            @unknown default: return "UIGestureRecognizerStateUnknown"
        }
    }
}
