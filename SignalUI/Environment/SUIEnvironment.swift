//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit

public class SUIEnvironment: NSObject {

    private static var _shared: SUIEnvironment = SUIEnvironment()

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

    public var audioSessionRef: AudioSession = AudioSession()

    public var contactsViewHelperRef: ContactsViewHelper = ContactsViewHelper()

    public var chatColorsRef: ChatColors = ChatColors()

    public var paymentsRef: Payments = PaymentsImpl()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    public func setup() {
        registerCustomFonts()
    }

    private func registerCustomFonts() {
        let bundle = Bundle(for: type(of: self))
        guard
            let ttfFontURLs = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil),
            let otfFontURLs = bundle.urls(forResourcesWithExtension: "otf", subdirectory: nil)
        else {
            return owsFailDebug("Failed to load fonts from bundle.")
        }
        for url in ttfFontURLs + otfFontURLs {
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
                let errorMessage = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "(unknown error)"
                owsFailDebug("Could not register font with url \(url): \(errorMessage)")
                continue
            }
        }
    }
}
