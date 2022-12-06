//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AppDelegate {
    @objc
    func applicationSwift(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if CurrentAppContext().isRunningTests || didAppLaunchFail {
            return .portrait
        }

        // The call-banner window is only suitable for portrait display on iPhone
        if CurrentAppContext().hasActiveCall, !UIDevice.current.isIPad {
            return .portrait
        }

        guard let rootViewController = self.window?.rootViewController else {
            return UIDevice.current.defaultSupportedOrientations
        }

        return rootViewController.supportedInterfaceOrientations
    }
}
