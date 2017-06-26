//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UIApplication {

    var frontmostViewController: UIViewController? {
        let window = UIApplication.shared.keyWindow
        var viewController = window!.rootViewController
        while viewController?.presentedViewController != nil {
            viewController = viewController?.presentedViewController
        }

        return viewController
    }

    func openSystemSettings() {
        openURL(URL(string: UIApplicationOpenSettingsURLString)!)
    }

}
