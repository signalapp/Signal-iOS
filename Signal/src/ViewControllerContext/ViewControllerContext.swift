//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Container for manager (business logic) objects that view controllers (or, better yet,
/// view models) interact with to query data and apply updates.
///
/// Alternative to `MainAppEnvironment` + `Dependencies` with a few advantages:
/// 1) Not a protocol + extension; you must explicitly access members via the shared instance
/// 2) Swift-only, no need for @objc
/// 3) Everything herein **should** adhere to modern design principles: NOT accessing
///   global state or `Dependencies`, being protocolized, and taking all dependencies
///   explicitly on initialization, encapsulated for easy testing.
public class ViewControllerContext {

    public let db: DB

    public let keyBackupService: KeyBackupServiceProtocol

    public let usernameLookupManager: UsernameLookupManager
    public let usernameEducationManager: UsernameEducationManager

    public init(
        db: DB,
        keyBackupService: KeyBackupServiceProtocol,
        usernameLookupManager: UsernameLookupManager,
        usernameEducationManager: UsernameEducationManager
    ) {
        self.db = db
        self.keyBackupService = keyBackupService
        self.usernameLookupManager = usernameLookupManager
        self.usernameEducationManager = usernameEducationManager
    }

    /// Eventually, this shared instance should not exist. (And DependenciesBridge should not exist, either).
    /// The ultimate goal is to create a single ViewControllerContext on main app startup, and pass
    /// it by reference everywhere it is needed (typically, every view controller).
    /// As a temporary stop-gap, we create a single shared instance which can be accessed from
    /// view controller several layers deep without having to pipe the context through from
    /// the AppDelegate.
    public static let shared: ViewControllerContext = {
        let bridge = DependenciesBridge.shared

        return ViewControllerContext(
            db: bridge.db,
            keyBackupService: bridge.keyBackupService,
            usernameLookupManager: bridge.usernameLookupManager,
            usernameEducationManager: bridge.usernameEducationManager
        )
    }()
}
