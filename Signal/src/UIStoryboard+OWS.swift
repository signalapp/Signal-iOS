//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UIStoryboard {
    private enum StoryboardName: String {
        case main = "Main"
    }

    class var main: UIStoryboard {
        return UIStoryboard(name: StoryboardName.main.rawValue, bundle: Bundle.main)
    }
}
