//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

@available(swift, obsoleted: 1)
@objc
public class AppContextObjcBridge: NSObject {
    @objc
    public static let owsApplicationWillResignActiveNotification = Notification.Name.OWSApplicationWillResignActive.rawValue
    @objc
    public static let owsApplicationDidBecomeActiveNotification = Notification.Name.OWSApplicationDidBecomeActive.rawValue

    @objc
    public static func CurrentAppContext() -> any AppContext { SignalServiceKit.CurrentAppContext() }
    @objc
    public static func SetCurrentAppContext(_ appContext: any AppContext) { SignalServiceKit.SetCurrentAppContext(appContext) }

    override private init() {}
}

// These are fired whenever the corresponding "main app" or "app extension"
// notification is fired.
//
// 1. This saves you the work of observing both.
// 2. This allows us to ensure that any critical work (e.g. re-opening
//    databases) has been done before app re-enters foreground, etc.
public extension Notification.Name {
    // TODO: Rename this to a more swift style name
    static let OWSApplicationDidEnterBackground = Notification.Name("OWSApplicationDidEnterBackgroundNotification")
    static let OWSApplicationWillEnterForeground = Notification.Name("OWSApplicationWillEnterForegroundNotification")
    static let OWSApplicationWillResignActive = Notification.Name("OWSApplicationWillResignActiveNotification")
    static let OWSApplicationDidBecomeActive = Notification.Name("OWSApplicationDidBecomeActiveNotification")
}

private var currentAppContext: (any AppContext)?

public func CurrentAppContext() -> any AppContext {
    // Yuck, but the objc function that came before this function lied about
    // not being able to return nil so the entire app is already written
    // assuming this can't be nil though it always could have been.
    currentAppContext!
}

public func SetCurrentAppContext(_ appContext: any AppContext) {
    currentAppContext = appContext
}
