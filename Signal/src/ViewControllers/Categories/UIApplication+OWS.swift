//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public extension UIApplication {

    var frontmostViewControllerIgnoringAlerts: UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        return findFrontmostViewController(ignoringAlerts: true, window: window)
    }

    @objc
    var frontmostViewController: UIViewController? {
        guard let window = CurrentAppContext().mainWindow else {
            return nil
        }
        return findFrontmostViewController(ignoringAlerts: false, window: window)
    }

    func findFrontmostViewController(ignoringAlerts: Bool, window: UIWindow) -> UIViewController? {
        Logger.verbose("findFrontmostViewController: \(window)")
        guard let viewController = window.rootViewController else {
            owsFailDebug("Missing root view controller.")
            return nil
        }
        return viewController.findFrontmostViewController(ignoringAlerts)
    }

    func openSystemSettings() {
        open(URL(string: UIApplication.openSettingsURLString)!, options: [:])
    }

    var keyWindow: UIWindow? {
        return windows.first(where: { $0.isKeyWindow })
    }

    var statusBarFrame: CGRect {
        return keyWindow?.windowScene?.statusBarManager?.statusBarFrame ?? .zero
    }

    var statusBarOrientation: UIInterfaceOrientation {
        return keyWindow?.windowScene?.interfaceOrientation ?? .unknown
    }
}
