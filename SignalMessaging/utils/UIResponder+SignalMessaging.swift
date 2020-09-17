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

    var disappearingMessagesJob: OWSDisappearingMessagesJob {
        return SSKEnvironment.shared.disappearingMessagesJob
    }

    static var disappearingMessagesJob: OWSDisappearingMessagesJob {
        return SSKEnvironment.shared.disappearingMessagesJob
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

    var launchJobs: LaunchJobs {
        return Environment.shared.launchJobs
    }

    static var launchJobs: LaunchJobs {
        return Environment.shared.launchJobs
    }

    var linkPreviewManager: OWSLinkPreviewManager {
        return SSKEnvironment.shared.linkPreviewManager
    }

    static var linkPreviewManager: OWSLinkPreviewManager {
        return SSKEnvironment.shared.linkPreviewManager
    }

    var messageFetcherJob: MessageFetcherJob {
        return SSKEnvironment.shared.messageFetcherJob
    }

    static var messageFetcherJob: MessageFetcherJob {
        return SSKEnvironment.shared.messageFetcherJob
    }

    var messageManager: OWSMessageManager {
        return SSKEnvironment.shared.messageManager
    }

    static var messageManager: OWSMessageManager {
        return SSKEnvironment.shared.messageManager
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

    var readReceiptManager: OWSReadReceiptManager {
        return OWSReadReceiptManager.shared()
    }

    static var readReceiptManager: OWSReadReceiptManager {
        return OWSReadReceiptManager.shared()
    }

    var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    static var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    var primaryStorage: OWSPrimaryStorage? {
        return SSKEnvironment.shared.primaryStorage
    }

    static var primaryStorage: OWSPrimaryStorage? {
        return SSKEnvironment.shared.primaryStorage
    }

    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    static var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    var socketManager: TSSocketManager {
        return SSKEnvironment.shared.socketManager
    }

    static var socketManager: TSSocketManager {
        return SSKEnvironment.shared.socketManager
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

    var syncManager: SyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
    }

    static var syncManager: SyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
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

    var windowManager: OWSWindowManager {
        return Environment.shared.windowManager
    }

    static var windowManager: OWSWindowManager {
        return Environment.shared.windowManager
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
