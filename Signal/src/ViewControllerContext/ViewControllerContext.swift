//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

/// Container for manager (business logic) objects that view controllers (or, better yet,
/// view models) interact with to query data and apply updates.
///
/// Alternative to `MainAppEnvironment` + `Dependencies` with a few advantages:
/// 1) Not a protocol + extension; you must explicitly access members via the shared instance
/// 2) Swift-only, no need for @objc
/// 3) Everything herein **should** adhere to modern design principles: NOT accessing
///   global state or `Dependencies`, being protocolized, and taking all dependencies
///   explicitly on initialization, encapsulated for easy testing.
final public class ViewControllerContext {

    public let db: any DB

    public let editManager: EditManager

    public let svr: SecureValueRecovery
    public let accountKeyStore: AccountKeyStore

    public let usernameApiClient: UsernameApiClient
    public let usernameEducationManager: UsernameEducationManager
    public let usernameLinkManager: UsernameLinkManager
    public let usernameLookupManager: UsernameLookupManager
    public let localUsernameManager: LocalUsernameManager

    public let provisioningManager: ProvisioningManager

    public init(
        db: any DB,
        editManager: EditManager,
        accountKeyStore: AccountKeyStore,
        svr: SecureValueRecovery,
        usernameApiClient: UsernameApiClient,
        usernameEducationManager: UsernameEducationManager,
        usernameLinkManager: UsernameLinkManager,
        usernameLookupManager: UsernameLookupManager,
        localUsernameManager: LocalUsernameManager,
        provisioningManager: ProvisioningManager
    ) {
        self.db = db
        self.editManager = editManager
        self.accountKeyStore = accountKeyStore
        self.svr = svr
        self.usernameApiClient = usernameApiClient
        self.usernameEducationManager = usernameEducationManager
        self.usernameLinkManager = usernameLinkManager
        self.usernameLookupManager = usernameLookupManager
        self.localUsernameManager = localUsernameManager
        self.provisioningManager = provisioningManager
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
            editManager: bridge.editManager,
            accountKeyStore: bridge.accountKeyStore,
            svr: bridge.svr,
            usernameApiClient: bridge.usernameApiClient,
            usernameEducationManager: bridge.usernameEducationManager,
            usernameLinkManager: bridge.usernameLinkManager,
            usernameLookupManager: bridge.usernameLookupManager,
            localUsernameManager: bridge.localUsernameManager,
            provisioningManager: AppEnvironment.shared.provisioningManager
        )
    }()
}
