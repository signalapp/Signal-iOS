//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - NSObject

@objc
public extension NSObject {

    final var preferences: Preferences {
        SMEnvironment.shared.preferencesRef
    }

    static var preferences: Preferences {
        SMEnvironment.shared.preferencesRef
    }

    final var profileManagerImpl: OWSProfileManager {
        profileManager as! OWSProfileManager
    }

    static var profileManagerImpl: OWSProfileManager {
        profileManager as! OWSProfileManager
    }

    final var contactsManagerImpl: OWSContactsManager {
        contactsManager as! OWSContactsManager
    }

    static var contactsManagerImpl: OWSContactsManager {
        contactsManager as! OWSContactsManager
    }

    final var groupsV2Impl: GroupsV2Impl {
        groupsV2 as! GroupsV2Impl
    }

    static var groupsV2Impl: GroupsV2Impl {
        groupsV2 as! GroupsV2Impl
    }

    final var groupV2UpdatesImpl: GroupV2UpdatesImpl {
        groupV2Updates as! GroupV2UpdatesImpl
    }

    static var groupV2UpdatesImpl: GroupV2UpdatesImpl {
        groupV2Updates as! GroupV2UpdatesImpl
    }

    var avatarBuilder: AvatarBuilder {
        SMEnvironment.shared.avatarBuilderRef
    }

    static var avatarBuilder: AvatarBuilder {
        SMEnvironment.shared.avatarBuilderRef
    }

    var lightweightCallManager: LightweightCallManager? {
        SMEnvironment.shared.lightweightCallManagerRef
    }

    static var lightweightCallManager: LightweightCallManager? {
        SMEnvironment.shared.lightweightCallManagerRef
    }

    var smJobQueues: SignalMessagingJobQueues {
        SMEnvironment.shared.smJobQueuesRef
    }

    static var smJobQueues: SignalMessagingJobQueues {
        SMEnvironment.shared.smJobQueuesRef
    }
}

// MARK: - Obj-C Dependencies

public extension Dependencies {

    var preferences: Preferences {
        SMEnvironment.shared.preferencesRef
    }

    static var preferences: Preferences {
        SMEnvironment.shared.preferencesRef
    }

    var profileManagerImpl: OWSProfileManager {
        profileManager as! OWSProfileManager
    }

    static var profileManagerImpl: OWSProfileManager {
        profileManager as! OWSProfileManager
    }

    var contactsManagerImpl: OWSContactsManager {
        contactsManager as! OWSContactsManager
    }

    static var contactsManagerImpl: OWSContactsManager {
        contactsManager as! OWSContactsManager
    }

    var groupsV2Impl: GroupsV2Impl {
        groupsV2 as! GroupsV2Impl
    }

    static var groupsV2Impl: GroupsV2Impl {
        groupsV2 as! GroupsV2Impl
    }

    var groupV2UpdatesImpl: GroupV2UpdatesImpl {
        groupV2Updates as! GroupV2UpdatesImpl
    }

    static var groupV2UpdatesImpl: GroupV2UpdatesImpl {
        groupV2Updates as! GroupV2UpdatesImpl
    }

    var avatarBuilder: AvatarBuilder {
        SMEnvironment.shared.avatarBuilderRef
    }

    static var avatarBuilder: AvatarBuilder {
        SMEnvironment.shared.avatarBuilderRef
    }

    var smJobQueues: SignalMessagingJobQueues {
        SMEnvironment.shared.smJobQueuesRef
    }

    static var smJobQueues: SignalMessagingJobQueues {
        SMEnvironment.shared.smJobQueuesRef
    }
}

// MARK: -

@objc
public extension OWSProfileManager {
    static var shared: OWSProfileManager {
        SSKEnvironment.shared.profileManagerRef as! OWSProfileManager
    }
}

// MARK: -

public extension OWSSyncManager {
    static var shared: SyncManagerProtocol {
        SSKEnvironment.shared.syncManagerRef
    }
}
