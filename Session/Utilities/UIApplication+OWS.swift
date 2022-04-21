// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit
import UIKit

@objc public extension UIApplication {

    var frontmostViewControllerIgnoringAlerts: UIViewController? {
        return findFrontmostViewController(ignoringAlerts: true)
    }

    var frontmostViewController: UIViewController? {
        return findFrontmostViewController(ignoringAlerts: false)
    }

    internal func findFrontmostViewController(ignoringAlerts: Bool) -> UIViewController? {
        guard let window: UIWindow = CurrentAppContext().mainWindow else { return nil }
        
        Logger.error("findFrontmostViewController: \(window)")
        
        guard let viewController: UIViewController = window.rootViewController else {
            owsFailDebug("Missing root view controller.")
            return nil
        }
        return viewController.findFrontmostViewController(ignoringAlerts)
    }

    func openSystemSettings() {
        openURL(URL(string: UIApplication.openSettingsURLString)!)
    }
}
