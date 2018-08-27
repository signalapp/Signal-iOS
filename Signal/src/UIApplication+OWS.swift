//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc public extension UIApplication {

    @objc public var frontmostViewControllerIgnoringAlerts: UIViewController? {
        return findFrontmostViewController(ignoringAlerts: true)
    }

    @objc public var frontmostViewController: UIViewController? {
        return findFrontmostViewController(ignoringAlerts: false)
    }

    internal func findFrontmostViewController(ignoringAlerts: Bool) -> UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        Logger.error("findFrontmostViewController: \(window)")
        guard let viewController = window.rootViewController else {
            owsFailDebug("Missing root view controller.")
            return nil
        }
        return viewController.findFrontmostViewController(ignoringAlerts)
    }

    @objc public func openSystemSettings() {
        openURL(URL(string: UIApplicationOpenSettingsURLString)!)
    }

}
