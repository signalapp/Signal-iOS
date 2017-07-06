//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UIApplication {

    var frontmostViewController: UIViewController? {
        let window = UIApplication.shared.keyWindow
        var viewController = window!.rootViewController
        
        while true {
            if let nextViewController = viewController?.presentedViewController {
                viewController = nextViewController
            } else if let navigationController = viewController as? UINavigationController {
                if let nextViewController = navigationController.topViewController {
                    viewController = nextViewController
                } else {
                    break
                }
            } else {
                break
            }
        }

        return viewController
    }

    func openSystemSettings() {
        openURL(URL(string: UIApplicationOpenSettingsURLString)!)
    }

}
