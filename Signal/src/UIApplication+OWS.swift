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
        guard let viewController = window!.rootViewController else {
            owsFail("\(self.logTag) in \(#function) Missing root view controller.")
            return nil
        }
        return viewController.findFrontmostViewController(ignoringAlerts)
    }

    func openSystemSettings() {
        openURL(URL(string: UIApplicationOpenSettingsURLString)!)
    }

}
