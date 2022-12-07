//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc
public class SUIEnvironment: NSObject {

    private static var _shared: SUIEnvironment = SUIEnvironment()

    @objc
    public class var shared: SUIEnvironment {
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
    public var audioSessionRef: AudioSession = AudioSession()

    @objc
    public var contactsViewHelperRef: ContactsViewHelper = ContactsViewHelper()

    @objc
    public var chatColorsRef: ChatColors = ChatColors()

    @objc
    public var paymentsRef: Payments = PaymentsImpl()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    @objc
    public func setup() {
        registerCustomFonts()
    }

    private func registerCustomFonts() {
        guard let fontUrls = Bundle(for: type(of: self)).urls(forResourcesWithExtension: "ttf", subdirectory: nil) else {
            return owsFailDebug("Failed to load fonts from bundle.")
        }
        for url in fontUrls {
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
                let errorMessage = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "(unknown error)"
                owsFailDebug("Could not register font with url \(url): \(errorMessage)")
                continue
            }
        }
    }
}
