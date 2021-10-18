//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc
public class UIEnvironment: NSObject {

    private static var _shared: UIEnvironment = UIEnvironment()

    @objc
    public class var shared: UIEnvironment {
        get {
            return _shared
        }
        set {
            guard CurrentAppContext().isRunningTests else {
                owsFailDebug("Can only switch environments in tests.")
                return
            }

            _shared = newValue
        }
    }

    @objc
    public var audioSessionRef: OWSAudioSession = OWSAudioSession()

    @objc
    public var windowManagerRef: OWSWindowManager = OWSWindowManager()

    @objc
    public var contactsViewHelperRef: ContactsViewHelper = ContactsViewHelper()

    @objc
    public var chatColorsRef: ChatColors = ChatColors()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    @objc
    public func setup() {
    }
}
