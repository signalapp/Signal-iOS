//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import UIKit

public extension UIApplication {
    var frontmostViewControllerIgnoringAlerts: UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        return window.findFrontmostViewController(ignoringAlerts: true)
    }

    @objc
    var frontmostViewController: UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        return window.findFrontmostViewController(ignoringAlerts: false)
    }

    func openSystemSettings() {
        open(URL(string: UIApplication.openSettingsURLString)!, options: [:])
    }
}

extension UIWindow {
    func findFrontmostViewController(ignoringAlerts: Bool) -> UIViewController? {
        guard let viewController = self.rootViewController else {
            owsFailDebug("Missing root view controller.")
            return nil
        }
        return viewController.findFrontmostViewController(ignoringAlerts: ignoringAlerts)
    }
}
