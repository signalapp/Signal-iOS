//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import UIKit

public extension UIDevice {

    @objc
    var isIPad: Bool {
        return userInterfaceIdiom == .pad
    }

    @objc
    var defaultSupportedOrientations: UIInterfaceOrientationMask {
        return isIPad ? .all : .allButUpsideDown
    }

    @objc
    func ows_setOrientation(_ orientation: UIDeviceOrientation) {
        // XXX - This is not officially supported, but there's no other way to programmatically rotate
        // the interface.
        let orientationKey = "orientation"
        self.setValue(orientation.rawValue, forKey: orientationKey)

        // Not strictly necessary for the orientation to appear as changed
        // but allegedly helps ensure related rotation delegate methods are called.
        // https://stackoverflow.com/questions/20987249/how-do-i-programmatically-set-device-orientation-in-ios7
        UINavigationController.attemptRotationToDeviceOrientation()
    }
}
