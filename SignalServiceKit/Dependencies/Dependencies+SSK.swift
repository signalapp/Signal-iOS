//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Exposes singleton accessors.
//
// Swift classes which do not subclass NSObject can implement Dependencies protocol.

public protocol Dependencies {}

// MARK: - NSObject

@objc
public extension NSObject {
    final var attachmentDownloads: OWSAttachmentDownloads {
        SSKEnvironment.shared.attachmentDownloadsRef
    }

    static var attachmentDownloads: OWSAttachmentDownloads {
        SSKEnvironment.shared.attachmentDownloadsRef
    }

    final var blockingManager: BlockingManager {
        .shared
    }

    static var blockingManager: BlockingManager {
        .shared
    }

    final var bulkProfileFetch: BulkProfileFetch {
        SSKEnvironment.shared.bulkProfileFetchRef
    }

    static var bulkProfileFetch: BulkProfileFetch {
        SSKEnvironment.shared.bulkProfileFetchRef
    }

    final var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    static var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    final var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }

    static var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }

    final var identityManager: OWSIdentityManager {
        SSKEnvironment.shared.identityManagerRef
    }

    static var identityManager: OWSIdentityManager {
        SSKEnvironment.shared.identityManagerRef
    }

    final var groupV2UpdatesObjc: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    static var groupV2UpdatesObjc: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    final var linkPreviewManager: OWSLinkPreviewManager {
        SSKEnvironment.shared.linkPreviewManagerRef
    }

    static var linkPreviewManager: OWSLinkPreviewManager {
        SSKEnvironment.shared.linkPreviewManagerRef
    }

    final var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJobRef
    }

    static var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJobRef
    }

    final var messageManager: OWSMessageManager {
        SSKEnvironment.shared.messageManagerRef
    }

    static var messageManager: OWSMessageManager {
        SSKEnvironment.shared.messageManagerRef
    }

    final var messageSender: MessageSender {
        SSKEnvironment.shared.messageSenderRef
    }

    static var messageSender: MessageSender {
        SSKEnvironment.shared.messageSenderRef
    }

    final var messagePipelineSupervisor: MessagePipelineSupervisor {
        SSKEnvironment.shared.messagePipelineSupervisorRef
    }

    static var messagePipelineSupervisor: MessagePipelineSupervisor {
        SSKEnvironment.shared.messagePipelineSupervisorRef
    }

    final var networkManager: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }

    static var networkManager: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }

    // This singleton is configured after the environments are created.
    final var notificationsManager: NotificationsProtocol? {
        SSKEnvironment.shared.notificationsManagerRef
    }

    // This singleton is configured after the environments are created.
    static var notificationsManager: NotificationsProtocol? {
        SSKEnvironment.shared.notificationsManagerRef
    }

    final var ows2FAManager: OWS2FAManager {
        .shared
    }

    static var ows2FAManager: OWS2FAManager {
        .shared
    }

    final var receiptManager: OWSReceiptManager {
        .shared
    }

    static var receiptManager: OWSReceiptManager {
        .shared
    }

    final var profileManager: ProfileManagerProtocol {
        SSKEnvironment.shared.profileManagerRef
    }

    static var profileManager: ProfileManagerProtocol {
        SSKEnvironment.shared.profileManagerRef
    }

    final var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManagerRef
    }

    static var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManagerRef
    }

    final var socketManager: SocketManager {
        SSKEnvironment.shared.socketManagerRef
    }

    static var socketManager: SocketManager {
        SSKEnvironment.shared.socketManagerRef
    }

    final var stickerManager: StickerManager {
        SSKEnvironment.shared.stickerManagerRef
    }

    static var stickerManager: StickerManager {
        SSKEnvironment.shared.stickerManagerRef
    }

    final var storageCoordinator: StorageCoordinator {
        SSKEnvironment.shared.storageCoordinatorRef
    }

    static var storageCoordinator: StorageCoordinator {
        SSKEnvironment.shared.storageCoordinatorRef
    }

    final var syncManager: SyncManagerProtocol {
        SSKEnvironment.shared.syncManagerRef
    }

    static var syncManager: SyncManagerProtocol {
        SSKEnvironment.shared.syncManagerRef
    }

    final var tsAccountManager: TSAccountManager {
        .shared
    }

    static var tsAccountManager: TSAccountManager {
        .shared
    }

    final var typingIndicatorsImpl: TypingIndicators {
        SSKEnvironment.shared.typingIndicatorsRef
    }

    static var typingIndicatorsImpl: TypingIndicators {
        SSKEnvironment.shared.typingIndicatorsRef
    }

    final var udManager: OWSUDManager {
        SSKEnvironment.shared.udManagerRef
    }

    static var udManager: OWSUDManager {
        SSKEnvironment.shared.udManagerRef
    }

    final var contactsManager: ContactsManagerProtocol {
        SSKEnvironment.shared.contactsManagerRef
    }

    static var contactsManager: ContactsManagerProtocol {
        SSKEnvironment.shared.contactsManagerRef
    }

    final var storageServiceManager: StorageServiceManagerProtocol {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    static var storageServiceManager: StorageServiceManagerProtocol {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    final var modelReadCaches: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }

    static var modelReadCaches: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }

    final var messageProcessor: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }

    static var messageProcessor: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }

    final var remoteConfigManager: RemoteConfigManager {
        SSKEnvironment.shared.remoteConfigManagerRef
    }

    static var remoteConfigManager: RemoteConfigManager {
        SSKEnvironment.shared.remoteConfigManagerRef
    }

    final var groupsV2: GroupsV2 {
        SSKEnvironment.shared.groupsV2Ref
    }

    static var groupsV2: GroupsV2 {
        SSKEnvironment.shared.groupsV2Ref
    }

    @objc(signalProtocolStoreForIdentity:)
    final func signalProtocolStore(for identity: OWSIdentity) -> SignalProtocolStore {
        SSKEnvironment.shared.signalProtocolStoreRef(for: identity)
    }

    @objc(signalProtocolStoreForIdentity:)
    static func signalProtocolStore(for identity: OWSIdentity) -> SignalProtocolStore {
        SSKEnvironment.shared.signalProtocolStoreRef(for: identity)
    }

    final var appExpiry: AppExpiry {
        SSKEnvironment.shared.appExpiryRef
    }

    static var appExpiry: AppExpiry {
        SSKEnvironment.shared.appExpiryRef
    }

    final var signalService: OWSSignalServiceProtocol {
        SSKEnvironment.shared.signalServiceRef
    }

    static var signalService: OWSSignalServiceProtocol {
        SSKEnvironment.shared.signalServiceRef
    }

    final var accountServiceClient: AccountServiceClient {
        SSKEnvironment.shared.accountServiceClientRef
    }

    static var accountServiceClient: AccountServiceClient {
        SSKEnvironment.shared.accountServiceClientRef
    }

    final var groupsV2MessageProcessor: GroupsV2MessageProcessor {
        SSKEnvironment.shared.groupsV2MessageProcessorRef
    }

    static var groupsV2MessageProcessor: GroupsV2MessageProcessor {
        SSKEnvironment.shared.groupsV2MessageProcessorRef
    }

    final var versionedProfiles: VersionedProfiles {
        SSKEnvironment.shared.versionedProfilesRef
    }

    static var versionedProfiles: VersionedProfiles {
        SSKEnvironment.shared.versionedProfilesRef
    }

    final var grdbStorageAdapter: GRDBDatabaseStorageAdapter {
        databaseStorage.grdbStorage
    }

    static var grdbStorageAdapter: GRDBDatabaseStorageAdapter {
        databaseStorage.grdbStorage
    }

    final var signalServiceAddressCache: SignalServiceAddressCache {
        SSKEnvironment.shared.signalServiceAddressCacheRef
    }

    static var signalServiceAddressCache: SignalServiceAddressCache {
        SSKEnvironment.shared.signalServiceAddressCacheRef
    }

    final var messageDecrypter: OWSMessageDecrypter {
        SSKEnvironment.shared.messageDecrypterRef
    }

    static var messageDecrypter: OWSMessageDecrypter {
        SSKEnvironment.shared.messageDecrypterRef
    }

    final var deviceManager: OWSDeviceManager {
        .shared()
    }

    static var deviceManager: OWSDeviceManager {
        .shared()
    }

    final var outgoingReceiptManager: OWSOutgoingReceiptManager {
        SSKEnvironment.shared.outgoingReceiptManagerRef
    }

    static var outgoingReceiptManager: OWSOutgoingReceiptManager {
        SSKEnvironment.shared.outgoingReceiptManagerRef
    }

    final var earlyMessageManager: EarlyMessageManager {
        SSKEnvironment.shared.earlyMessageManagerRef
    }

    static var earlyMessageManager: EarlyMessageManager {
        SSKEnvironment.shared.earlyMessageManagerRef
    }

    // This singleton is configured after the environments are created.
    final var callMessageHandler: OWSCallMessageHandler? {
        SSKEnvironment.shared.callMessageHandlerRef
    }

    // This singleton is configured after the environments are created.
    static var callMessageHandler: OWSCallMessageHandler? {
        SSKEnvironment.shared.callMessageHandlerRef
    }

    final var pendingReceiptRecorder: PendingReceiptRecorder {
        SSKEnvironment.shared.pendingReceiptRecorderRef
    }

    static var pendingReceiptRecorder: PendingReceiptRecorder {
        SSKEnvironment.shared.pendingReceiptRecorderRef
    }

    final var outageDetection: OutageDetection {
        .shared
    }

    static var outageDetection: OutageDetection {
        .shared
    }

    final var notificationPresenter: NotificationsProtocol? {
        SSKEnvironment.shared.notificationsManager
    }

    static var notificationPresenter: NotificationsProtocol? {
        SSKEnvironment.shared.notificationsManager
    }

    final var paymentsHelper: PaymentsHelper {
        SSKEnvironment.shared.paymentsHelperRef
    }

    static var paymentsHelper: PaymentsHelper {
        SSKEnvironment.shared.paymentsHelperRef
    }

    final var paymentsCurrencies: PaymentsCurrencies {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    static var paymentsCurrencies: PaymentsCurrencies {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    final var paymentsEvents: PaymentsEvents {
        SSKEnvironment.shared.paymentsEventsRef
    }

    static var paymentsEvents: PaymentsEvents {
        SSKEnvironment.shared.paymentsEventsRef
    }

    final var mobileCoinHelper: MobileCoinHelper {
        SSKEnvironment.shared.mobileCoinHelperRef
    }

    static var mobileCoinHelper: MobileCoinHelper {
        SSKEnvironment.shared.mobileCoinHelperRef
    }

    final var spamChallengeResolver: SpamChallengeResolver {
        SSKEnvironment.shared.spamChallengeResolverRef
    }

    static var spamChallengeResolver: SpamChallengeResolver {
        SSKEnvironment.shared.spamChallengeResolverRef
    }

    final var senderKeyStore: SenderKeyStore {
        SSKEnvironment.shared.senderKeyStoreRef
    }

    static var senderKeyStore: SenderKeyStore {
        SSKEnvironment.shared.senderKeyStoreRef
    }

    final var appVersion: AppVersion {
        AppVersion.shared()
    }

    static var appVersion: AppVersion {
        AppVersion.shared()
    }

    final var phoneNumberUtil: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }

    static var phoneNumberUtil: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }

    var legacyChangePhoneNumber: LegacyChangePhoneNumber {
        SSKEnvironment.shared.legacyChangePhoneNumberRef
    }

    static var legacyChangePhoneNumber: LegacyChangePhoneNumber {
        SSKEnvironment.shared.legacyChangePhoneNumberRef
    }

    var subscriptionManager: SubscriptionManager {
        SSKEnvironment.shared.subscriptionManagerRef
    }

    static var subscriptionManager: SubscriptionManager {
        SSKEnvironment.shared.subscriptionManagerRef
    }

    @nonobjc
    var systemStoryManager: SystemStoryManagerProtocol {
        SSKEnvironment.shared.systemStoryManagerRef as! SystemStoryManagerProtocol
    }

    @nonobjc
    static var systemStoryManager: SystemStoryManagerProtocol {
        SSKEnvironment.shared.systemStoryManagerRef as! SystemStoryManagerProtocol
    }

    var sskJobQueues: SSKJobQueues {
        SSKEnvironment.shared.sskJobQueuesRef
    }

    static var sskJobQueues: SSKJobQueues {
        SSKEnvironment.shared.sskJobQueuesRef
    }

    @nonobjc
    var contactDiscoveryManager: ContactDiscoveryManager {
        SSKEnvironment.shared.contactDiscoveryManagerRef as! ContactDiscoveryManager
    }

    @nonobjc
    static var contactDiscoveryManager: ContactDiscoveryManager {
        SSKEnvironment.shared.contactDiscoveryManagerRef as! ContactDiscoveryManager
    }
}

// MARK: - Obj-C Dependencies

public extension Dependencies {

    var attachmentDownloads: OWSAttachmentDownloads {
        SSKEnvironment.shared.attachmentDownloadsRef
    }

    static var attachmentDownloads: OWSAttachmentDownloads {
        SSKEnvironment.shared.attachmentDownloadsRef
    }

    var blockingManager: BlockingManager {
        .shared
    }

    static var blockingManager: BlockingManager {
        .shared
    }

    var bulkProfileFetch: BulkProfileFetch {
        SSKEnvironment.shared.bulkProfileFetchRef
    }

    static var bulkProfileFetch: BulkProfileFetch {
        SSKEnvironment.shared.bulkProfileFetchRef
    }

    var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    static var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }

    static var disappearingMessagesJob: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }

    var identityManager: OWSIdentityManager {
        SSKEnvironment.shared.identityManagerRef
    }

    static var identityManager: OWSIdentityManager {
        SSKEnvironment.shared.identityManagerRef
    }

    var groupV2UpdatesObjc: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    static var groupV2UpdatesObjc: GroupV2Updates {
        SSKEnvironment.shared.groupV2UpdatesRef
    }

    var linkPreviewManager: OWSLinkPreviewManager {
        SSKEnvironment.shared.linkPreviewManagerRef
    }

    static var linkPreviewManager: OWSLinkPreviewManager {
        SSKEnvironment.shared.linkPreviewManagerRef
    }

    var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJobRef
    }

    static var messageFetcherJob: MessageFetcherJob {
        SSKEnvironment.shared.messageFetcherJobRef
    }

    var messageManager: OWSMessageManager {
        SSKEnvironment.shared.messageManagerRef
    }

    static var messageManager: OWSMessageManager {
        SSKEnvironment.shared.messageManagerRef
    }

    var messageSender: MessageSender {
        SSKEnvironment.shared.messageSenderRef
    }

    static var messageSender: MessageSender {
        SSKEnvironment.shared.messageSenderRef
    }

    var messagePipelineSupervisor: MessagePipelineSupervisor {
        SSKEnvironment.shared.messagePipelineSupervisorRef
    }

    static var messagePipelineSupervisor: MessagePipelineSupervisor {
        SSKEnvironment.shared.messagePipelineSupervisorRef
    }

    var networkManager: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }

    static var networkManager: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }

    // This singleton is configured after the environments are created.
    var notificationsManager: NotificationsProtocol? {
        SSKEnvironment.shared.notificationsManagerRef
    }

    // This singleton is configured after the environments are created.
    static var notificationsManager: NotificationsProtocol? {
        SSKEnvironment.shared.notificationsManagerRef
    }

    var ows2FAManager: OWS2FAManager {
        .shared
    }

    static var ows2FAManager: OWS2FAManager {
        .shared
    }

    var receiptManager: OWSReceiptManager {
        .shared
    }

    static var receiptManager: OWSReceiptManager {
        .shared
    }

    var profileManager: ProfileManagerProtocol {
        SSKEnvironment.shared.profileManagerRef
    }

    static var profileManager: ProfileManagerProtocol {
        SSKEnvironment.shared.profileManagerRef
    }

    var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManagerRef
    }

    static var reachabilityManager: SSKReachabilityManager {
        SSKEnvironment.shared.reachabilityManagerRef
    }

    var socketManager: SocketManager {
        SSKEnvironment.shared.socketManagerRef
    }

    static var socketManager: SocketManager {
        SSKEnvironment.shared.socketManagerRef
    }

    var stickerManager: StickerManager {
        SSKEnvironment.shared.stickerManagerRef
    }

    static var stickerManager: StickerManager {
        SSKEnvironment.shared.stickerManagerRef
    }

    var storageCoordinator: StorageCoordinator {
        SSKEnvironment.shared.storageCoordinatorRef
    }

    static var storageCoordinator: StorageCoordinator {
        SSKEnvironment.shared.storageCoordinatorRef
    }

    var syncManager: SyncManagerProtocol {
        SSKEnvironment.shared.syncManagerRef
    }

    static var syncManager: SyncManagerProtocol {
        SSKEnvironment.shared.syncManagerRef
    }

    var tsAccountManager: TSAccountManager {
        .shared
    }

    static var tsAccountManager: TSAccountManager {
        .shared
    }

    var typingIndicatorsImpl: TypingIndicators {
        SSKEnvironment.shared.typingIndicatorsRef
    }

    static var typingIndicatorsImpl: TypingIndicators {
        SSKEnvironment.shared.typingIndicatorsRef
    }

    var udManager: OWSUDManager {
        SSKEnvironment.shared.udManagerRef
    }

    static var udManager: OWSUDManager {
        SSKEnvironment.shared.udManagerRef
    }

    var contactsManager: ContactsManagerProtocol {
        SSKEnvironment.shared.contactsManagerRef
    }

    static var contactsManager: ContactsManagerProtocol {
        SSKEnvironment.shared.contactsManagerRef
    }

    var storageServiceManager: StorageServiceManagerProtocol {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    static var storageServiceManager: StorageServiceManagerProtocol {
        SSKEnvironment.shared.storageServiceManagerRef
    }

    var modelReadCaches: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }

    static var modelReadCaches: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }

    var messageProcessor: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }

    static var messageProcessor: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }

    var remoteConfigManager: RemoteConfigManager {
        SSKEnvironment.shared.remoteConfigManagerRef
    }

    static var remoteConfigManager: RemoteConfigManager {
        SSKEnvironment.shared.remoteConfigManagerRef
    }

    var groupsV2: GroupsV2 {
        SSKEnvironment.shared.groupsV2Ref
    }

    static var groupsV2: GroupsV2 {
        SSKEnvironment.shared.groupsV2Ref
    }

    func signalProtocolStore(for identity: OWSIdentity) -> SignalProtocolStore {
        SSKEnvironment.shared.signalProtocolStoreRef(for: identity)
    }

    static func signalProtocolStore(for identity: OWSIdentity) -> SignalProtocolStore {
        SSKEnvironment.shared.signalProtocolStoreRef(for: identity)
    }

    var appExpiry: AppExpiry {
        SSKEnvironment.shared.appExpiryRef
    }

    static var appExpiry: AppExpiry {
        SSKEnvironment.shared.appExpiryRef
    }

    var signalService: OWSSignalServiceProtocol {
        SSKEnvironment.shared.signalServiceRef
    }

    static var signalService: OWSSignalServiceProtocol {
        SSKEnvironment.shared.signalServiceRef
    }

    var accountServiceClient: AccountServiceClient {
        SSKEnvironment.shared.accountServiceClientRef
    }

    static var accountServiceClient: AccountServiceClient {
        SSKEnvironment.shared.accountServiceClientRef
    }

    var groupsV2MessageProcessor: GroupsV2MessageProcessor {
        SSKEnvironment.shared.groupsV2MessageProcessorRef
    }

    static var groupsV2MessageProcessor: GroupsV2MessageProcessor {
        SSKEnvironment.shared.groupsV2MessageProcessorRef
    }

    var versionedProfiles: VersionedProfiles {
        SSKEnvironment.shared.versionedProfilesRef
    }

    static var versionedProfiles: VersionedProfiles {
        SSKEnvironment.shared.versionedProfilesRef
    }

    var grdbStorageAdapter: GRDBDatabaseStorageAdapter {
        databaseStorage.grdbStorage
    }

    static var grdbStorageAdapter: GRDBDatabaseStorageAdapter {
        databaseStorage.grdbStorage
    }

    var signalServiceAddressCache: SignalServiceAddressCache {
        SSKEnvironment.shared.signalServiceAddressCacheRef
    }

    static var signalServiceAddressCache: SignalServiceAddressCache {
        SSKEnvironment.shared.signalServiceAddressCacheRef
    }

    var messageDecrypter: OWSMessageDecrypter {
        SSKEnvironment.shared.messageDecrypterRef
    }

    static var messageDecrypter: OWSMessageDecrypter {
        SSKEnvironment.shared.messageDecrypterRef
    }

    var deviceManager: OWSDeviceManager {
        .shared()
    }

    static var deviceManager: OWSDeviceManager {
        .shared()
    }

    var outgoingReceiptManager: OWSOutgoingReceiptManager {
        SSKEnvironment.shared.outgoingReceiptManagerRef
    }

    static var outgoingReceiptManager: OWSOutgoingReceiptManager {
        SSKEnvironment.shared.outgoingReceiptManagerRef
    }

    var earlyMessageManager: EarlyMessageManager {
        SSKEnvironment.shared.earlyMessageManagerRef
    }

    static var earlyMessageManager: EarlyMessageManager {
        SSKEnvironment.shared.earlyMessageManagerRef
    }

    // This singleton is configured after the environments are created.
    var callMessageHandler: OWSCallMessageHandler? {
        SSKEnvironment.shared.callMessageHandlerRef
    }

    // This singleton is configured after the environments are created.
    static var callMessageHandler: OWSCallMessageHandler? {
        SSKEnvironment.shared.callMessageHandlerRef
    }

    var pendingReceiptRecorder: PendingReceiptRecorder {
        SSKEnvironment.shared.pendingReceiptRecorderRef
    }

    static var pendingReceiptRecorder: PendingReceiptRecorder {
        SSKEnvironment.shared.pendingReceiptRecorderRef
    }

    var outageDetection: OutageDetection {
        .shared
    }

    static var outageDetection: OutageDetection {
        .shared
    }

    var notificationPresenter: NotificationsProtocol? {
        SSKEnvironment.shared.notificationsManager
    }

    static var notificationPresenter: NotificationsProtocol? {
        SSKEnvironment.shared.notificationsManager
    }

    var paymentsHelper: PaymentsHelper {
        SSKEnvironment.shared.paymentsHelperRef
    }

    static var paymentsHelper: PaymentsHelper {
        SSKEnvironment.shared.paymentsHelperRef
    }

    var paymentsCurrencies: PaymentsCurrencies {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    static var paymentsCurrencies: PaymentsCurrencies {
        SSKEnvironment.shared.paymentsCurrenciesRef
    }

    var paymentsEvents: PaymentsEvents {
        SSKEnvironment.shared.paymentsEventsRef
    }

    static var paymentsEvents: PaymentsEvents {
        SSKEnvironment.shared.paymentsEventsRef
    }

    var mobileCoinHelper: MobileCoinHelper {
        SSKEnvironment.shared.mobileCoinHelperRef
    }

    static var mobileCoinHelper: MobileCoinHelper {
        SSKEnvironment.shared.mobileCoinHelperRef
    }

    var spamChallengeResolver: SpamChallengeResolver {
        SSKEnvironment.shared.spamChallengeResolverRef
    }

    static var spamChallengeResolver: SpamChallengeResolver {
        SSKEnvironment.shared.spamChallengeResolverRef
    }

    var senderKeyStore: SenderKeyStore {
        SSKEnvironment.shared.senderKeyStoreRef
    }

    static var senderKeyStore: SenderKeyStore {
        SSKEnvironment.shared.senderKeyStoreRef
    }

    var appVersion: AppVersion {
        AppVersion.shared()
    }

    static var appVersion: AppVersion {
        AppVersion.shared()
    }

    var phoneNumberUtil: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }

    static var phoneNumberUtil: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }

    var webSocketFactory: WebSocketFactory {
        SSKEnvironment.shared.webSocketFactoryRef as! WebSocketFactory
    }

    static var webSocketFactory: WebSocketFactory {
        SSKEnvironment.shared.webSocketFactoryRef as! WebSocketFactory
    }

    var legacyChangePhoneNumber: LegacyChangePhoneNumber {
        SSKEnvironment.shared.legacyChangePhoneNumberRef
    }

    static var legacyChangePhoneNumber: LegacyChangePhoneNumber {
        SSKEnvironment.shared.legacyChangePhoneNumberRef
    }

    var subscriptionManager: SubscriptionManager {
        SSKEnvironment.shared.subscriptionManagerRef
    }

    static var subscriptionManager: SubscriptionManager {
        SSKEnvironment.shared.subscriptionManagerRef
    }

    var systemStoryManager: SystemStoryManagerProtocol {
        SSKEnvironment.shared.systemStoryManagerRef as! SystemStoryManagerProtocol
    }

    static var systemStoryManager: SystemStoryManagerProtocol {
        SSKEnvironment.shared.systemStoryManagerRef as! SystemStoryManagerProtocol
    }

    var sskJobQueues: SSKJobQueues {
        SSKEnvironment.shared.sskJobQueuesRef
    }

    static var sskJobQueues: SSKJobQueues {
        SSKEnvironment.shared.sskJobQueuesRef
    }

    var contactDiscoveryManager: ContactDiscoveryManager {
        SSKEnvironment.shared.contactDiscoveryManagerRef as! ContactDiscoveryManager
    }

    static var contactDiscoveryManager: ContactDiscoveryManager {
        SSKEnvironment.shared.contactDiscoveryManagerRef as! ContactDiscoveryManager
    }
}

// MARK: - Swift-only Dependencies

public extension NSObject {

    final var groupsV2Swift: GroupsV2Swift {
        SSKEnvironment.shared.groupsV2Ref as! GroupsV2Swift
    }

    static var groupsV2Swift: GroupsV2Swift {
        SSKEnvironment.shared.groupsV2Ref as! GroupsV2Swift
    }

    final var groupV2Updates: GroupV2UpdatesSwift {
        SSKEnvironment.shared.groupV2UpdatesRef as! GroupV2UpdatesSwift
    }

    static var groupV2Updates: GroupV2UpdatesSwift {
        SSKEnvironment.shared.groupV2UpdatesRef as! GroupV2UpdatesSwift
    }

    final var serviceClient: SignalServiceClient {
        SignalServiceRestClient.shared
    }

    static var serviceClient: SignalServiceClient {
        SignalServiceRestClient.shared
    }

    final var paymentsHelperSwift: PaymentsHelperSwift {
        SSKEnvironment.shared.paymentsHelperRef as! PaymentsHelperSwift
    }

    static var paymentsHelperSwift: PaymentsHelperSwift {
        SSKEnvironment.shared.paymentsHelperRef as! PaymentsHelperSwift
    }

    final var paymentsCurrenciesSwift: PaymentsCurrenciesSwift {
        SSKEnvironment.shared.paymentsCurrenciesRef as! PaymentsCurrenciesSwift
    }

    static var paymentsCurrenciesSwift: PaymentsCurrenciesSwift {
        SSKEnvironment.shared.paymentsCurrenciesRef as! PaymentsCurrenciesSwift
    }

    var versionedProfilesSwift: VersionedProfilesSwift {
        versionedProfiles as! VersionedProfilesSwift
    }

    static var versionedProfilesSwift: VersionedProfilesSwift {
        versionedProfiles as! VersionedProfilesSwift
    }
}

// MARK: - Swift-only Dependencies

public extension Dependencies {

    var groupsV2Swift: GroupsV2Swift {
        SSKEnvironment.shared.groupsV2Ref as! GroupsV2Swift
    }

    static var groupsV2Swift: GroupsV2Swift {
        SSKEnvironment.shared.groupsV2Ref as! GroupsV2Swift
    }

    var groupV2Updates: GroupV2UpdatesSwift {
        SSKEnvironment.shared.groupV2UpdatesRef as! GroupV2UpdatesSwift
    }

    static var groupV2Updates: GroupV2UpdatesSwift {
        SSKEnvironment.shared.groupV2UpdatesRef as! GroupV2UpdatesSwift
    }

    var serviceClient: SignalServiceClient {
        SignalServiceRestClient.shared
    }

    static var serviceClient: SignalServiceClient {
        SignalServiceRestClient.shared
    }

    var paymentsHelperSwift: PaymentsHelperSwift {
        SSKEnvironment.shared.paymentsHelperRef as! PaymentsHelperSwift
    }

    static var paymentsHelperSwift: PaymentsHelperSwift {
        SSKEnvironment.shared.paymentsHelperRef as! PaymentsHelperSwift
    }

    var paymentsCurrenciesSwift: PaymentsCurrenciesSwift {
        SSKEnvironment.shared.paymentsCurrenciesRef as! PaymentsCurrenciesSwift
    }

    static var paymentsCurrenciesSwift: PaymentsCurrenciesSwift {
        SSKEnvironment.shared.paymentsCurrenciesRef as! PaymentsCurrenciesSwift
    }

    var versionedProfilesSwift: VersionedProfilesSwift {
        versionedProfiles as! VersionedProfilesSwift
    }

    static var versionedProfilesSwift: VersionedProfilesSwift {
        versionedProfiles as! VersionedProfilesSwift
    }
}

// MARK: -

@objc
public extension BlockingManager {
    static var shared: BlockingManager {
        SSKEnvironment.shared.blockingManagerRef
    }
}

// MARK: -

@objc
public extension SDSDatabaseStorage {
    static var shared: SDSDatabaseStorage {
        SSKEnvironment.shared.databaseStorageRef
    }
}

// MARK: -

@objc
public extension OWS2FAManager {
    static var shared: OWS2FAManager {
        SSKEnvironment.shared.ows2FAManagerRef
    }
}

// MARK: -

@objc
public extension OWSReceiptManager {
    static var shared: OWSReceiptManager {
        SSKEnvironment.shared.receiptManagerRef
    }
}

// MARK: -

@objc
public extension TSAccountManager {
    static var shared: TSAccountManager {
        SSKEnvironment.shared.tsAccountManagerRef
    }
}

// MARK: -

@objc
public extension AppExpiry {
    static var shared: AppExpiry {
        SSKEnvironment.shared.appExpiryRef
    }
}

// MARK: -

@objc
public extension StickerManager {
    static var shared: StickerManager {
        SSKEnvironment.shared.stickerManagerRef
    }
}

// MARK: -

@objc
public extension ModelReadCaches {
    static var shared: ModelReadCaches {
        SSKEnvironment.shared.modelReadCachesRef
    }
}

// MARK: -

@objc
public extension SSKPreferences {
    static var shared: SSKPreferences {
        SSKEnvironment.shared.sskPreferencesRef
    }
}

// MARK: -

@objc
public extension MessageProcessor {
    static var shared: MessageProcessor {
        SSKEnvironment.shared.messageProcessorRef
    }
}

// MARK: -

@objc
public extension SocketManager {
    static var shared: SocketManager {
        SSKEnvironment.shared.socketManagerRef
    }
}

// MARK: -

@objc
public extension NetworkManager {
    static var shared: NetworkManager {
        SSKEnvironment.shared.networkManagerRef
    }
}

// MARK: -

@objc
public extension OWSOutgoingReceiptManager {
    static var shared: OWSOutgoingReceiptManager {
        SSKEnvironment.shared.outgoingReceiptManagerRef
    }
}

// MARK: -

@objc
public extension OWSIdentityManager {
    static var shared: OWSIdentityManager {
        SSKEnvironment.shared.identityManagerRef
    }
}

// MARK: -

@objc
public extension OWSDisappearingMessagesJob {
    static var shared: OWSDisappearingMessagesJob {
        SSKEnvironment.shared.disappearingMessagesJobRef
    }
}

// MARK: -

@objc
public extension PhoneNumberUtil {
    static var shared: PhoneNumberUtil {
        SSKEnvironment.shared.phoneNumberUtilRef
    }
}
