//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

extension UIStoryboard {
    private enum StoryboardName: String {
        case main = "Main"
    }

    class var main: UIStoryboard {
        return UIStoryboard(name: StoryboardName.main.rawValue, bundle: Bundle.main)
    }
}
