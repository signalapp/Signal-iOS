//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUtilitiesKit
import SignalUtilitiesKit

@objc(OWSWebRTCCallMessageHandler)
public class WebRTCCallMessageHandler: NSObject/*, OWSCallMessageHandler*/ {

    // MARK: Initializers

    @objc
    public override init()
    {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Dependencies

    private var accountManager : AccountManager
    {
        return AppEnvironment.shared.accountManager
    }
}
