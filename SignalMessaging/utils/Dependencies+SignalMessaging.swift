//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - NSObject

@objc
public extension NSObject {
    final var preferences: Preferences {
        Environment.shared.preferencesRef
    }

    static var preferences: Preferences {
        Environment.shared.preferencesRef
    }

    final var proximityMonitoringManager: OWSProximityMonitoringManager {
        Environment.shared.proximityMonitoringManagerRef
    }

    static var proximityMonitoringManager: OWSProximityMonitoringManager {
        Environment.shared.proximityMonitoringManagerRef
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
        Environment.shared.avatarBuilderRef
    }

    static var avatarBuilder: AvatarBuilder {
        Environment.shared.avatarBuilderRef
    }

    var lightweightCallManager: LightweightCallManager? {
        Environment.shared.lightweightCallManagerRef
    }

    static var lightweightCallManager: LightweightCallManager? {
        Environment.shared.lightweightCallManagerRef
    }

    var smJobQueues: SignalMessagingJobQueues {
        Environment.shared.signalMessagingJobQueuesRef
    }

    static var smJobQueues: SignalMessagingJobQueues {
        Environment.shared.signalMessagingJobQueuesRef
    }
}

// MARK: - Obj-C Dependencies

public extension Dependencies {
    var preferences: Preferences {
        Environment.shared.preferencesRef
    }

    static var preferences: Preferences {
        Environment.shared.preferencesRef
    }

    var proximityMonitoringManager: OWSProximityMonitoringManager {
        Environment.shared.proximityMonitoringManagerRef
    }

    static var proximityMonitoringManager: OWSProximityMonitoringManager {
        Environment.shared.proximityMonitoringManagerRef
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
        Environment.shared.avatarBuilderRef
    }

    static var avatarBuilder: AvatarBuilder {
        Environment.shared.avatarBuilderRef
    }

    var smJobQueues: SignalMessagingJobQueues {
        Environment.shared.signalMessagingJobQueuesRef
    }

    static var smJobQueues: SignalMessagingJobQueues {
        Environment.shared.signalMessagingJobQueuesRef
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
