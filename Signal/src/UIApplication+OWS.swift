//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UIApplication {

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
        Logger.error("findFrontmostViewController: \(window)")
        guard let viewController = window.rootViewController else {
            owsFail("\(self.logTag) in \(#function) Missing root view controller.")
            return nil
        }
        return viewController.findFrontmostViewController(ignoringAlerts)
    }

    func openSystemSettings() {
        openURL(URL(string: UIApplicationOpenSettingsURLString)!)
    }

}
