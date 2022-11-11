//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - NSObject

@objc
public extension NSObject {
    final var launchJobs: LaunchJobs {
        Environment.shared.launchJobsRef
    }

    static var launchJobs: LaunchJobs {
        Environment.shared.launchJobsRef
    }

    final var preferences: OWSPreferences {
        Environment.shared.preferencesRef
    }

    static var preferences: OWSPreferences {
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

    final var sounds: OWSSounds {
        Environment.shared.soundsRef
    }

    static var sounds: OWSSounds {
        Environment.shared.soundsRef
    }

    final var orphanDataCleaner: OWSOrphanDataCleaner {
        Environment.shared.orphanDataCleanerRef
    }

    static var orphanDataCleaner: OWSOrphanDataCleaner {
        Environment.shared.orphanDataCleanerRef
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
    var launchJobs: LaunchJobs {
        Environment.shared.launchJobsRef
    }

    static var launchJobs: LaunchJobs {
        Environment.shared.launchJobsRef
    }

    var preferences: OWSPreferences {
        Environment.shared.preferencesRef
    }

    static var preferences: OWSPreferences {
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

    var sounds: OWSSounds {
        Environment.shared.soundsRef
    }

    static var sounds: OWSSounds {
        Environment.shared.soundsRef
    }

    var orphanDataCleaner: OWSOrphanDataCleaner {
        Environment.shared.orphanDataCleanerRef
    }

    static var orphanDataCleaner: OWSOrphanDataCleaner {
        Environment.shared.orphanDataCleanerRef
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

// MARK: - Swift-only Dependencies

public extension NSObject {
    var versionedProfilesSwift: VersionedProfilesSwift {
        versionedProfiles as! VersionedProfilesSwift
    }

    static var versionedProfilesSwift: VersionedProfilesSwift {
        versionedProfiles as! VersionedProfilesSwift
    }
}

// MARK: - Swift-only Dependencies

public extension Dependencies {
    var versionedProfilesSwift: VersionedProfilesSwift {
        versionedProfiles as! VersionedProfilesSwift
    }

    static var versionedProfilesSwift: VersionedProfilesSwift {
        versionedProfiles as! VersionedProfilesSwift
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

@objc
public extension OWSSounds {
    static var shared: OWSSounds {
        Environment.shared.soundsRef
    }
}

// MARK: -

@objc
public extension OWSSyncManager {
    static var shared: SyncManagerProtocol {
        SSKEnvironment.shared.syncManagerRef
    }
}
