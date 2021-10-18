//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// MARK: - NSObject

@objc
public extension NSObject {
    final var audioSession: OWSAudioSession {
        UIEnvironment.shared.audioSessionRef
    }

    static var audioSession: OWSAudioSession {
        UIEnvironment.shared.audioSessionRef
    }

    final var contactsViewHelper: ContactsViewHelper {
        UIEnvironment.shared.contactsViewHelperRef
    }

    static var contactsViewHelper: ContactsViewHelper {
        UIEnvironment.shared.contactsViewHelperRef
    }

    final var fullTextSearcher: FullTextSearcher { .shared }

    static var fullTextSearcher: FullTextSearcher { .shared }

//    final var launchJobs: LaunchJobs {
//        UIEnvironment.shared.launchJobsRef
//    }
//
//    static var launchJobs: LaunchJobs {
//        UIEnvironment.shared.launchJobsRef
//    }
//
//    final var preferences: OWSPreferences {
//        UIEnvironment.shared.preferencesRef
//    }
//
//    static var preferences: OWSPreferences {
//        UIEnvironment.shared.preferencesRef
//    }

    final var windowManager: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }

    static var windowManager: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }

//    final var proximityMonitoringManager: OWSProximityMonitoringManager {
//        UIEnvironment.shared.proximityMonitoringManagerRef
//    }
//
//    static var proximityMonitoringManager: OWSProximityMonitoringManager {
//        UIEnvironment.shared.proximityMonitoringManagerRef
//    }
//
//    final var profileManagerImpl: OWSProfileManager {
//        profileManager as! OWSProfileManager
//    }
//
//    static var profileManagerImpl: OWSProfileManager {
//        profileManager as! OWSProfileManager
//    }
//
//    final var contactsManagerImpl: OWSContactsManager {
//        contactsManager as! OWSContactsManager
//    }
//
//    static var contactsManagerImpl: OWSContactsManager {
//        contactsManager as! OWSContactsManager
//    }
//
//    final var groupsV2Impl: GroupsV2Impl {
//        groupsV2 as! GroupsV2Impl
//    }
//
//    static var groupsV2Impl: GroupsV2Impl {
//        groupsV2 as! GroupsV2Impl
//    }
//
//    final var groupV2UpdatesImpl: GroupV2UpdatesImpl {
//        groupV2Updates as! GroupV2UpdatesImpl
//    }
//
//    static var groupV2UpdatesImpl: GroupV2UpdatesImpl {
//        groupV2Updates as! GroupV2UpdatesImpl
//    }
//
//    final var versionedProfilesImpl: VersionedProfilesImpl {
//        versionedProfiles as! VersionedProfilesImpl
//    }
//
//    static var versionedProfilesImpl: VersionedProfilesImpl {
//        versionedProfiles as! VersionedProfilesImpl
//    }
//
//    final var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue {
//        UIEnvironment.shared.broadcastMediaMessageJobQueueRef
//    }
//
//    static var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue {
//        UIEnvironment.shared.broadcastMediaMessageJobQueueRef
//    }
//
//    final var sounds: OWSSounds {
//        UIEnvironment.shared.soundsRef
//    }
//
//    static var sounds: OWSSounds {
//        UIEnvironment.shared.soundsRef
//    }
//
//    final var incomingContactSyncJobQueue: IncomingContactSyncJobQueue {
//        UIEnvironment.shared.incomingContactSyncJobQueueRef
//    }
//
//    static var incomingContactSyncJobQueue: IncomingContactSyncJobQueue {
//        UIEnvironment.shared.incomingContactSyncJobQueueRef
//    }
//
//    final var incomingGroupSyncJobQueue: IncomingGroupSyncJobQueue {
//        UIEnvironment.shared.incomingGroupSyncJobQueueRef
//    }
//
//    static var incomingGroupSyncJobQueue: IncomingGroupSyncJobQueue {
//        UIEnvironment.shared.incomingGroupSyncJobQueueRef
//    }
//
//    final var orphanDataCleaner: OWSOrphanDataCleaner {
//        UIEnvironment.shared.orphanDataCleanerRef
//    }
//
//    static var orphanDataCleaner: OWSOrphanDataCleaner {
//        UIEnvironment.shared.orphanDataCleanerRef
//    }
//
//    final var paymentsImpl: PaymentsImpl {
//        SSKEnvironment.shared.paymentsRef as! PaymentsImpl
//    }
//
//    static var paymentsImpl: PaymentsImpl {
//        SSKEnvironment.shared.paymentsRef as! PaymentsImpl
//    }

    var chatColors: ChatColors {
        UIEnvironment.shared.chatColorsRef
    }

    static var chatColors: ChatColors {
        UIEnvironment.shared.chatColorsRef
    }

//    var avatarBuilder: AvatarBuilder {
//        UIEnvironment.shared.avatarBuilderRef
//    }
//
//    static var avatarBuilder: AvatarBuilder {
//        UIEnvironment.shared.avatarBuilderRef
//    }
}

// MARK: - Obj-C Dependencies

public extension Dependencies {
    var audioSession: OWSAudioSession {
        UIEnvironment.shared.audioSessionRef
    }

    static var audioSession: OWSAudioSession {
        UIEnvironment.shared.audioSessionRef
    }

    var contactsViewHelper: ContactsViewHelper {
        UIEnvironment.shared.contactsViewHelperRef
    }

    static var contactsViewHelper: ContactsViewHelper {
        UIEnvironment.shared.contactsViewHelperRef
    }

    var fullTextSearcher: FullTextSearcher { .shared }

    static var fullTextSearcher: FullTextSearcher { .shared }

//    var launchJobs: LaunchJobs {
//        UIEnvironment.shared.launchJobsRef
//    }
//
//    static var launchJobs: LaunchJobs {
//        UIEnvironment.shared.launchJobsRef
//    }
//
//    var preferences: OWSPreferences {
//        UIEnvironment.shared.preferencesRef
//    }
//
//    static var preferences: OWSPreferences {
//        UIEnvironment.shared.preferencesRef
//    }

    var windowManager: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }

    static var windowManager: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }

//    var proximityMonitoringManager: OWSProximityMonitoringManager {
//        UIEnvironment.shared.proximityMonitoringManagerRef
//    }
//
//    static var proximityMonitoringManager: OWSProximityMonitoringManager {
//        UIEnvironment.shared.proximityMonitoringManagerRef
//    }
//
//    var profileManagerImpl: OWSProfileManager {
//        profileManager as! OWSProfileManager
//    }
//
//    static var profileManagerImpl: OWSProfileManager {
//        profileManager as! OWSProfileManager
//    }
//
//    var contactsManagerImpl: OWSContactsManager {
//        contactsManager as! OWSContactsManager
//    }
//
//    static var contactsManagerImpl: OWSContactsManager {
//        contactsManager as! OWSContactsManager
//    }
//
//    var groupsV2Impl: GroupsV2Impl {
//        groupsV2 as! GroupsV2Impl
//    }
//
//    static var groupsV2Impl: GroupsV2Impl {
//        groupsV2 as! GroupsV2Impl
//    }
//
//    var groupV2UpdatesImpl: GroupV2UpdatesImpl {
//        groupV2Updates as! GroupV2UpdatesImpl
//    }
//
//    static var groupV2UpdatesImpl: GroupV2UpdatesImpl {
//        groupV2Updates as! GroupV2UpdatesImpl
//    }
//
//    var versionedProfilesImpl: VersionedProfilesImpl {
//        versionedProfiles as! VersionedProfilesImpl
//    }
//
//    static var versionedProfilesImpl: VersionedProfilesImpl {
//        versionedProfiles as! VersionedProfilesImpl
//    }
//
//    var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue {
//        UIEnvironment.shared.broadcastMediaMessageJobQueueRef
//    }
//
//    static var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue {
//        UIEnvironment.shared.broadcastMediaMessageJobQueueRef
//    }
//
//    var sounds: OWSSounds {
//        UIEnvironment.shared.soundsRef
//    }
//
//    static var sounds: OWSSounds {
//        UIEnvironment.shared.soundsRef
//    }
//
//    var incomingContactSyncJobQueue: IncomingContactSyncJobQueue {
//        UIEnvironment.shared.incomingContactSyncJobQueueRef
//    }
//
//    static var incomingContactSyncJobQueue: IncomingContactSyncJobQueue {
//        UIEnvironment.shared.incomingContactSyncJobQueueRef
//    }
//
//    var incomingGroupSyncJobQueue: IncomingGroupSyncJobQueue {
//        UIEnvironment.shared.incomingGroupSyncJobQueueRef
//    }
//
//    static var incomingGroupSyncJobQueue: IncomingGroupSyncJobQueue {
//        UIEnvironment.shared.incomingGroupSyncJobQueueRef
//    }
//
//    var orphanDataCleaner: OWSOrphanDataCleaner {
//        UIEnvironment.shared.orphanDataCleanerRef
//    }
//
//    static var orphanDataCleaner: OWSOrphanDataCleaner {
//        UIEnvironment.shared.orphanDataCleanerRef
//    }
//
//    var paymentsImpl: PaymentsImpl {
//        SSKEnvironment.shared.paymentsRef as! PaymentsImpl
//    }
//
//    static var paymentsImpl: PaymentsImpl {
//        SSKEnvironment.shared.paymentsRef as! PaymentsImpl
//    }

    var chatColors: ChatColors {
        UIEnvironment.shared.chatColorsRef
    }

    static var chatColors: ChatColors {
        UIEnvironment.shared.chatColorsRef
    }

//    var avatarBuilder: AvatarBuilder {
//        UIEnvironment.shared.avatarBuilderRef
//    }
//
//    static var avatarBuilder: AvatarBuilder {
//        UIEnvironment.shared.avatarBuilderRef
//    }
}

// MARK: - Swift-only Dependencies

public extension NSObject {
}

// MARK: - Swift-only Dependencies

public extension Dependencies {
}

// MARK: -

// @objc
// public extension OWSProfileManager {
//    static var shared: OWSProfileManager {
//        SSKEnvironment.shared.profileManagerRef as! OWSProfileManager
//    }
// }
//
// MARK: -
//
// @objc
// public extension OWSSounds {
//    static var shared: OWSSounds {
//        UIEnvironment.shared.soundsRef
//    }
// }

 MARK: -

 @objc
 public extension OWSWindowManager {
    static var shared: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }
 }

 MARK: -

// @objc
// public extension OWSSyncManager {
//    static var shared: SyncManagerProtocol {
//        SSKEnvironment.shared.syncManagerRef
//    }
// }
