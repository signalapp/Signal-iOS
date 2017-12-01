//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UIApplication {

    var frontmostViewControllerIgnoringAlerts: UIViewController? {
        return findFrontmostViewController(ignoringAlerts:true)
    }

    var frontmostViewController: UIViewController? {
        return findFrontmostViewController(ignoringAlerts:false)
    }

    internal func findFrontmostViewController(ignoringAlerts: Bool) -> UIViewController? {
        let window = UIApplication.shared.keyWindow
        var viewController = window!.rootViewController
        return viewController.findFrontmostViewController(ignoringAlerts:ignoringAlerts)
    }

    func openSystemSettings() {
        openURL(URL(string: UIApplicationOpenSettingsURLString)!)
    }

}
