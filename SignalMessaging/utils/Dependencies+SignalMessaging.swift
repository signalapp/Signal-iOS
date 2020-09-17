//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// Exposes singleton accessors for all UIViews, UIViewControllers, etc.
@objc
public extension UIResponder {

    // MARK: - Dependencies

    var audioSession: OWSAudioSession {
        Environment.shared.audioSession
    }

    static var audioSession: OWSAudioSession {
        Environment.shared.audioSession
    }

    var attachmentDownloads: OWSAttachmentDownloads {
        SSKEnvironment.shared.attachmentDownloads
    }

    static var attachmentDownloads: OWSAttachmentDownloads {
        SSKEnvironment.shared.attachmentDownloads
    }

    var blockingManager: OWSBlockingManager {
        .shared()
    }

    static var blockingManager: OWSBlockingManager {
        .shared()
    }

    var bulkProfileFetch: BulkProfileFetch {
        SSKEnvironment.shared.bulkProfileFetch
    }

    static var bulkProfileFetch: BulkProfileFetch {
        SSKEnvironment.shared.bulkProfileFetch
    }

    var contactsManager: OWSContactsManager {
        Environment.shared.contactsManager
    }

    static var contactsManager: OWSContactsManager {
        Environment.shared.contactsManager
    }

    var contactsViewHelper: ContactsViewHelper {
        Environment.shared.contactsViewHelper
    }

    static var contactsViewHelper: ContactsViewHelper {
        Environment.shared.contactsViewHelper
    }

    var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    static var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJob
    }

    static var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJob
    }

    var fullTextSearcher: FullTextSearcher { .shared }

    static var fullTextSearcher: FullTextSearcher { .shared }

    var identityManager: OWSIdentityManager {
        SSKEnvironment.shared.identityManager
    }

    static var identityManager: OWSIdentityManager {
        SSKEnvironment.shared.identityManager
    }

    var groupV2UpdatesObjc: GroupV2Updates {
        SSKEnvironment.shared.groupV2Updates
    }

    static var groupV2UpdatesObjc: GroupV2Updates {
        SSKEnvironment.shared.groupV2Updates
    }

    var launchJobs: LaunchJobs {
        Environment.shared.launchJobs
    }

    static var launchJobs: LaunchJobs {
        Environment.shared.launchJobs
    }

    var linkPreviewManager: OWSLinkPreviewManager {
        SSKEnvironment.shared.linkPreviewManager
    }

    static var linkPreviewManager: OWSLinkPreviewManager {
        SSKEnvironment.shared.linkPreviewManager
    }

    var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJob
    }

    static var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJob
    }

    var messageManager: OWSMessageManager {
        SSKEnvironment.shared.messageManager
    }

    static var messageManager: OWSMessageManager {
        SSKEnvironment.shared.messageManager
    }

    var messageSender: MessageSender {
        SSKEnvironment.shared.messageSender
    }

    static var messageSender: MessageSender {
        SSKEnvironment.shared.messageSender
    }

    var messageSenderJobQueue: MessageSenderJobQueue {
        SSKEnvironment.shared.messageSenderJobQueue
    }

    static var messageSenderJobQueue: MessageSenderJobQueue {
        SSKEnvironment.shared.messageSenderJobQueue
    }

    var networkManager: TSNetworkManager {
        SSKEnvironment.shared.networkManager
    }

    static var networkManager: TSNetworkManager {
        SSKEnvironment.shared.networkManager
    }

    var ows2FAManager: OWS2FAManager {
        .shared()
    }

    static var ows2FAManager: OWS2FAManager {
        .shared()
    }

    var readReceiptManager: OWSReadReceiptManager {
        OWSReadReceiptManager.shared()
    }

    static var readReceiptManager: OWSReadReceiptManager {
        OWSReadReceiptManager.shared()
    }

    var preferences: OWSPreferences {
        Environment.shared.preferences
    }

    static var preferences: OWSPreferences {
        Environment.shared.preferences
    }

    var primaryStorage: OWSPrimaryStorage? {
        SSKEnvironment.shared.primaryStorage
    }

    static var primaryStorage: OWSPrimaryStorage? {
        SSKEnvironment.shared.primaryStorage
    }

    var profileManager: OWSProfileManager {
        OWSProfileManager.shared()
    }

    static var profileManager: OWSProfileManager {
        OWSProfileManager.shared()
    }

    var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManager
    }

    static var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManager
    }

    var socketManager: TSSocketManager {
        SSKEnvironment.shared.socketManager
    }

    static var socketManager: TSSocketManager {
        SSKEnvironment.shared.socketManager
    }

    var stickerManager: StickerManager {
        SSKEnvironment.shared.stickerManager
    }

    static var stickerManager: StickerManager {
        SSKEnvironment.shared.stickerManager
    }

    var storageCoordinator: StorageCoordinator {
        SSKEnvironment.shared.storageCoordinator
    }

    static var storageCoordinator: StorageCoordinator {
        SSKEnvironment.shared.storageCoordinator
    }

    var syncManager: SyncManagerProtocol {
        SSKEnvironment.shared.syncManager
    }

    static var syncManager: SyncManagerProtocol {
        SSKEnvironment.shared.syncManager
    }

    var tsAccountManager: TSAccountManager {
        .shared()
    }

    static var tsAccountManager: TSAccountManager {
        .shared()
    }

    var typingIndicators: TypingIndicators {
        SSKEnvironment.shared.typingIndicators
    }

    static var typingIndicators: TypingIndicators {
        SSKEnvironment.shared.typingIndicators
    }

    var udManager: OWSUDManager {
        SSKEnvironment.shared.udManager
    }

    static var udManager: OWSUDManager {
        SSKEnvironment.shared.udManager
    }

    var windowManager: OWSWindowManager {
        Environment.shared.windowManager
    }

    static var windowManager: OWSWindowManager {
        Environment.shared.windowManager
    }
}

// MARK: -

public extension UIResponder {

    // MARK: - Dependencies

    var groupsV2: GroupsV2Swift {
        SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    static var groupsV2: GroupsV2Swift {
        SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    var groupV2Updates: GroupV2UpdatesSwift {
        SSKEnvironment.shared.groupV2Updates as! GroupV2UpdatesSwift
    }

    static var groupV2Updates: GroupV2UpdatesSwift {
        SSKEnvironment.shared.groupV2Updates as! GroupV2UpdatesSwift
    }
}
