//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// Exposes singleton accessors for all UIViews, UIViewControllers, etc.
@objc
public extension UIResponder {

    // MARK: - Dependencies

    var blockingManager: OWSBlockingManager {
        return .shared()
    }

    static var blockingManager: OWSBlockingManager {
        return .shared()
    }

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    static var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    var contactsViewHelper: ContactsViewHelper {
        return Environment.shared.contactsViewHelper
    }

    static var contactsViewHelper: ContactsViewHelper {
        return Environment.shared.contactsViewHelper
    }

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    var identityManager: OWSIdentityManager {
        return SSKEnvironment.shared.identityManager
    }

    static var identityManager: OWSIdentityManager {
        return SSKEnvironment.shared.identityManager
    }

//    @objc
//    @available(swift, obsoleted: 1.0)
//    var groupsV2: GroupsV2 {
//        return SSKEnvironment.shared.groupsV2
//    }
//    
//    @objc
//    @available(swift, obsoleted: 1.0)
//    static var groupsV2: GroupsV2 {
//        return SSKEnvironment.shared.groupsV2
//    }

    var linkPreviewManager: OWSLinkPreviewManager {
        return SSKEnvironment.shared.linkPreviewManager
    }

    static var linkPreviewManager: OWSLinkPreviewManager {
        return SSKEnvironment.shared.linkPreviewManager
    }

    var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    static var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    static var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    var ows2FAManager: OWS2FAManager {
        return .shared()
    }

    static var ows2FAManager: OWS2FAManager {
        return .shared()
    }

    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    static var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    var stickerManager: StickerManager {
        return SSKEnvironment.shared.stickerManager
    }

    static var stickerManager: StickerManager {
        return SSKEnvironment.shared.stickerManager
    }

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    static var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    var tsAccountManager: TSAccountManager {
        return .shared()
    }

    static var tsAccountManager: TSAccountManager {
        return .shared()
    }

    var udManager: OWSUDManager {
        return SSKEnvironment.shared.udManager
    }

    static var udManager: OWSUDManager {
        return SSKEnvironment.shared.udManager
    }
}

// MARK: -

public extension UIResponder {

    // MARK: - Dependencies

    var groupsV2: GroupsV2Swift {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    static var groupsV2: GroupsV2Swift {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    var groupV2Updates: GroupV2UpdatesSwift {
        return SSKEnvironment.shared.groupV2Updates as! GroupV2UpdatesSwift
    }

    static var groupV2Updates: GroupV2UpdatesSwift {
        return SSKEnvironment.shared.groupV2Updates as! GroupV2UpdatesSwift
    }
}
