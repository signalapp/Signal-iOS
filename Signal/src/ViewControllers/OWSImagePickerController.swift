//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging

class OWSImagePickerController: UIImagePickerController {

    // MARK: Orientation

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.defaultSupportedOrientations
    }
}
