//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// MARK: - NSObject

@objc
public extension NSObject {

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

    var avatarBuilder: AvatarBuilder {
        SMEnvironment.shared.avatarBuilderRef
    }

    static var avatarBuilder: AvatarBuilder {
        SMEnvironment.shared.avatarBuilderRef
    }

    var lightweightGroupCallManager: LightweightGroupCallManager? {
        SMEnvironment.shared.lightweightGroupCallManagerRef
    }

    static var lightweightGroupCallManager: LightweightGroupCallManager? {
        SMEnvironment.shared.lightweightGroupCallManagerRef
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
