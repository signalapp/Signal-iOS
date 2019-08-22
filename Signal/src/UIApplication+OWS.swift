//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc public extension UIApplication {

    var frontmostViewControllerIgnoringAlerts: UIViewController? {
        return findFrontmostViewController(ignoringAlerts: true)
    }

    var frontmostViewController: UIViewController? {
        return findFrontmostViewController(ignoringAlerts: false)
    }

    internal func findFrontmostViewController(ignoringAlerts: Bool) -> UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        Logger.verbose("findFrontmostViewController: \(window)")
        guard let viewController = window.rootViewController else {
            owsFailDebug("Missing root view controller.")
            return nil
        }
        return viewController.findFrontmostViewController(ignoringAlerts)
    }

    func openSystemSettings() {
        openURL(URL(string: UIApplication.openSettingsURLString)!)
    }

}
