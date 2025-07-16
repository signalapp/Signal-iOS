//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension BackupArchive {
    /// An identifier for the ``BackupProto_AccountData`` backup frame.
    ///
    /// Uses a singleton pattern, as there is only ever one account data frame
    /// in a backup.
    public struct AccountDataId: BackupArchive.LoggableId {
        static let localUser = AccountDataId()

        static func forCustomChatColorError(chatColorId: CustomChatColorId) -> Self {
            return .init(chatColorId)
        }

        /// Since custom chat colors are included in account data, errors can be nested
        /// with an account data -> chat color id
        private let chatColorId: CustomChatColorId?

        private init(_ chatColorId: CustomChatColorId? = nil) {
            self.chatColorId = chatColorId
        }

        // MARK: BackupArchive.LoggableId

        public var typeLogString: String {
            if chatColorId != nil {
                return "BackupProto_AccountData_CustomChatColor"
            } else {
                return "BackupProto_AccountData"
            }
        }

        public var idLogString: String {
            if let chatColorId {
                return "localUser_\(chatColorId.value)"
            } else {
                return "localUser"
            }
        }
    }

    public typealias ArchiveAccountDataResult = ArchiveSingleFrameResult<Void, AccountDataId>
    public typealias RestoreAccountDataResult = RestoreFrameResult<BackupArchive.AccountDataId>
}

/// Archives the ``BackupProto_AccountData`` frame.
public class BackupArchiveAccountDataArchiver: BackupArchiveProtoStreamWriter {
    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let backupPlanManager: BackupPlanManager
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let chatStyleArchiver: BackupArchiveChatStyleArchiver
    private let disappearingMessageConfigurationStore: DisappearingMessagesConfigurationStore
    private let donationSubscriptionManager: BackupArchive.Shims.DonationSubscriptionManager
    private let linkPreviewSettingStore: LinkPreviewSettingStore
    private let localUsernameManager: LocalUsernameManager
    private let ows2FAManager: BackupArchive.Shims.OWS2FAManager
    private let phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager
    private let preferences: BackupArchive.Shims.Preferences
    private let profileManager: BackupArchive.Shims.ProfileManager
    private let receiptManager: BackupArchive.Shims.ReceiptManager
    private let reactionManager: BackupArchive.Shims.ReactionManager
    private let sskPreferences: BackupArchive.Shims.SSKPreferences
    private let storyManager: BackupArchive.Shims.StoryManager
    private let systemStoryManager: BackupArchive.Shims.SystemStoryManager
    private let typingIndicators: BackupArchive.Shims.TypingIndicators
    private let udManager: BackupArchive.Shims.UDManager
    private let usernameEducationManager: UsernameEducationManager

    public init(
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupPlanManager: BackupPlanManager,
        backupSubscriptionManager: BackupSubscriptionManager,
        chatStyleArchiver: BackupArchiveChatStyleArchiver,
        disappearingMessageConfigurationStore: DisappearingMessagesConfigurationStore,
        donationSubscriptionManager: BackupArchive.Shims.DonationSubscriptionManager,
        linkPreviewSettingStore: LinkPreviewSettingStore,
        localUsernameManager: LocalUsernameManager,
        ows2FAManager: BackupArchive.Shims.OWS2FAManager,
        phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager,
        preferences: BackupArchive.Shims.Preferences,
        profileManager: BackupArchive.Shims.ProfileManager,
        receiptManager: BackupArchive.Shims.ReceiptManager,
        reactionManager: BackupArchive.Shims.ReactionManager,
        sskPreferences: BackupArchive.Shims.SSKPreferences,
        storyManager: BackupArchive.Shims.StoryManager,
        systemStoryManager: BackupArchive.Shims.SystemStoryManager,
        typingIndicators: BackupArchive.Shims.TypingIndicators,
        udManager: BackupArchive.Shims.UDManager,
        usernameEducationManager: UsernameEducationManager
    ) {
        self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
        self.backupPlanManager = backupPlanManager
        self.backupSubscriptionManager = backupSubscriptionManager
        self.chatStyleArchiver = chatStyleArchiver
        self.disappearingMessageConfigurationStore = disappearingMessageConfigurationStore
        self.donationSubscriptionManager = donationSubscriptionManager
        self.linkPreviewSettingStore = linkPreviewSettingStore
        self.localUsernameManager = localUsernameManager
        self.ows2FAManager = ows2FAManager
        self.phoneNumberDiscoverabilityManager = phoneNumberDiscoverabilityManager
        self.preferences = preferences
        self.profileManager = profileManager
        self.receiptManager = receiptManager
        self.reactionManager = reactionManager
        self.sskPreferences = sskPreferences
        self.storyManager = storyManager
        self.systemStoryManager = systemStoryManager
        self.typingIndicators = typingIndicators
        self.udManager = udManager
        self.usernameEducationManager = usernameEducationManager
    }

    // MARK: -

    func archiveAccountData(
        stream: BackupArchiveProtoOutputStream,
        context: BackupArchive.CustomChatColorArchivingContext
    ) -> BackupArchive.ArchiveAccountDataResult {
        return context.bencher.processFrame { frameBencher in
            guard let localProfile = profileManager.getUserProfileForLocalUser(tx: context.tx) else {
                return .failure(.archiveFrameError(.missingLocalProfile, .localUser))
            }
            guard let profileKeyData = localProfile.profileKey?.keyData else {
                return .failure(.archiveFrameError(.missingLocalProfileKey, .localUser))
            }

            var accountData = BackupProto_AccountData()
            accountData.profileKey = profileKeyData
            accountData.givenName = localProfile.givenName ?? ""
            accountData.familyName = localProfile.familyName ?? ""
            accountData.avatarURLPath = localProfile.avatarUrlPath ?? ""

            if let donationSubscriberId = donationSubscriptionManager.getSubscriberID(tx: context.tx) {
                var donationSubscriberData = BackupProto_AccountData.SubscriberData()
                donationSubscriberData.subscriberID = donationSubscriberId
                donationSubscriberData.currencyCode = donationSubscriptionManager.getSubscriberCurrencyCode(tx: context.tx) ?? ""
                donationSubscriberData.manuallyCancelled = donationSubscriptionManager.userManuallyCancelledSubscription(tx: context.tx)

                accountData.donationSubscriberData = donationSubscriberData
            }

            if let result = buildUsernameLinkProto(context: context) {
                accountData.username = result.username
                accountData.usernameLink = result.usernameLink
            }

            let accountSettingsResult = buildAccountSettingsProto(context: context)
            switch accountSettingsResult {
            case .success(let accountSettings):
                accountData.accountSettings = accountSettings
            case .failure(let error):
                return .failure(error)
            }

            if let iapSubscriberData = backupSubscriptionManager.getIAPSubscriberData(tx: context.tx) {
                var iapSubscriberDataProto = BackupProto_AccountData.IAPSubscriberData()
                iapSubscriberDataProto.subscriberID = iapSubscriberData.subscriberId
                iapSubscriberDataProto.iapSubscriptionID = switch iapSubscriberData.iapSubscriptionId {
                case .originalTransactionId(let value): .originalTransactionID(value)
                case .purchaseToken(let value): .purchaseToken(value)
                }

                accountData.backupsSubscriberData = iapSubscriberDataProto
            }

            if
                context.includedContentFilter.shouldIncludePin,
                let pin = ows2FAManager.getPin(tx: context.tx)
            {
                accountData.svrPin = pin
            }

            let error = Self.writeFrameToStream(
                stream,
                objectId: BackupArchive.AccountDataId.localUser,
                frameBencher: frameBencher
            ) {
                var frame = BackupProto_Frame()
                frame.item = .account(accountData)
                return frame
            }

            if let error {
                return .failure(error)
            } else {
                return .success(())
            }
        }
    }

    private func buildUsernameLinkProto(
        context: BackupArchive.ArchivingContext
    ) -> (username: String, usernameLink: BackupProto_AccountData.UsernameLink)? {
        switch self.localUsernameManager.usernameState(tx: context.tx) {
        case .unset, .linkCorrupted, .usernameAndLinkCorrupted:
            return nil
        case .available(let username, let usernameLink):
            var usernameLinkProto = BackupProto_AccountData.UsernameLink()
            usernameLinkProto.entropy = usernameLink.entropy
            usernameLinkProto.serverID = usernameLink.handle.data
            usernameLinkProto.color = localUsernameManager.usernameLinkQRCodeColor(tx: context.tx).backupProtoColor

            return (username, usernameLinkProto)
        }
    }

    private func buildAccountSettingsProto(
        context: BackupArchive.CustomChatColorArchivingContext
    ) -> BackupArchive.ArchiveSingleFrameResult<BackupProto_AccountData.AccountSettings, BackupArchive.AccountDataId> {

        // Fetch all the account settings
        let readReceipts = receiptManager.areReadReceiptsEnabled(tx: context.tx)
        let sealedSenderIndicators = preferences.shouldShowUnidentifiedDeliveryIndicators(tx: context.tx)
        let typingIndicatorsEnabled = typingIndicators.areTypingIndicatorsEnabled()
        let linkPreviews = linkPreviewSettingStore.areLinkPreviewsEnabled(tx: context.tx)
        let notDiscoverableByPhoneNumber = switch phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: context.tx) {
        case .everybody: false
        case .nobody, .none: true
        }
        let preferContactAvatars = sskPreferences.preferContactAvatars(tx: context.tx)
        let universalExpireTimerSeconds = disappearingMessageConfigurationStore.fetchOrBuildDefault(
            for: .universal,
            tx: context.tx
        ).durationSeconds
        let displayBadgesOnProfile = donationSubscriptionManager.displayBadgesOnProfile(tx: context.tx)
        let keepMutedChatsArchived = sskPreferences.shouldKeepMutedChatsArchived(tx: context.tx)
        let hasSetMyStoriesPrivacy = storyManager.hasSetMyStoriesPrivacy(tx: context.tx)
        let hasViewedOnboardingStory = systemStoryManager.isOnboardingStoryViewed(tx: context.tx)
        let storiesDisabled = storyManager.areStoriesEnabled(tx: context.tx).negated
        let hasSeenGroupStoryEducationSheet = systemStoryManager.hasSeenGroupStoryEducationSheet(tx: context.tx)
        let hasCompletedUsernameOnboarding = usernameEducationManager.shouldShowUsernameEducation(tx: context.tx).negated
        let phoneNumberSharingMode: BackupProto_AccountData.PhoneNumberSharingMode = switch udManager.phoneNumberSharingMode(tx: context.tx).orDefault {
        case .everybody: .everybody
        case .nobody: .nobody
        }

        // Populate the proto with the settings
        var accountSettings = BackupProto_AccountData.AccountSettings()
        accountSettings.readReceipts = readReceipts
        accountSettings.sealedSenderIndicators = sealedSenderIndicators
        accountSettings.typingIndicators = typingIndicatorsEnabled
        accountSettings.linkPreviews = linkPreviews
        accountSettings.notDiscoverableByPhoneNumber = notDiscoverableByPhoneNumber
        accountSettings.preferContactAvatars = preferContactAvatars
        accountSettings.universalExpireTimerSeconds = universalExpireTimerSeconds
        accountSettings.displayBadgesOnProfile = displayBadgesOnProfile
        accountSettings.keepMutedChatsArchived = keepMutedChatsArchived
        accountSettings.hasSetMyStoriesPrivacy_p = hasSetMyStoriesPrivacy
        accountSettings.hasViewedOnboardingStory_p = hasViewedOnboardingStory
        accountSettings.storiesDisabled = storiesDisabled
        accountSettings.hasSeenGroupStoryEducationSheet_p = hasSeenGroupStoryEducationSheet
        accountSettings.hasCompletedUsernameOnboarding_p = hasCompletedUsernameOnboarding
        accountSettings.phoneNumberSharingMode = phoneNumberSharingMode
        accountSettings.preferredReactionEmoji = reactionManager.customEmojiSet(tx: context.tx) ?? []
        accountSettings.storyViewReceiptsEnabled = storyManager.areViewReceiptsEnabled(tx: context.tx)
        switch backupPlanManager.backupPlan(tx: context.tx) {
        case .disabling, .disabled:
            accountSettings.clearBackupTier()
            accountSettings.optimizeOnDeviceStorage = false
        case .free:
            accountSettings.backupTier = UInt64(BackupLevel.free.rawValue)
            accountSettings.optimizeOnDeviceStorage = false
        case .paid(let optimizeLocalStorage), .paidExpiringSoon(let optimizeLocalStorage), .paidAsTester(let optimizeLocalStorage):
            accountSettings.backupTier = UInt64(BackupLevel.paid.rawValue)
            accountSettings.optimizeOnDeviceStorage = optimizeLocalStorage
        }

        let customChatColorsResult = chatStyleArchiver.archiveCustomChatColors(
            context: context
        )
        switch customChatColorsResult {
        case .success(let customChatColors):
            accountSettings.customChatColors = customChatColors
        case .failure(let error):
            return .failure(error)
        }

        // This has to happen _after_ we archive custom chat colors, because
        // the default chat style might use a custom chat color.
        let defaultChatStyleResult = chatStyleArchiver.archiveDefaultChatStyle(
            context: context
        )
        switch defaultChatStyleResult {
        case .success(let chatStyleProto):
            if let chatStyleProto {
                accountSettings.defaultChatStyle = chatStyleProto
            }
        case .failure(let archiveFrameError):
            return .failure(archiveFrameError)
        }

        return .success(accountSettings)
    }

    // MARK: -

    func restore(
        _ accountData: BackupProto_AccountData,
        context: BackupArchive.AccountDataRestoringContext,
        chatColorsContext: BackupArchive.CustomChatColorRestoringContext,
        chatItemContext: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreAccountDataResult {
        guard let profileKey = Aes256Key(data: accountData.profileKey) else {
            return .failure([.restoreFrameError(
                .invalidProtoData(.invalidLocalProfileKey),
                .localUser
            )])
        }

        var partialErrors = [BackupArchive.RestoreFrameError<BackupArchive.AccountDataId>]()

        // Given name and profile key are required for the local profile. The
        // rest are optional.
        profileManager.insertLocalUserProfile(
            givenName: accountData.givenName,
            familyName: accountData.familyName.nilIfEmpty,
            avatarUrlPath: accountData.avatarURLPath.nilIfEmpty,
            profileKey: profileKey,
            tx: context.tx
        )

        // Restore donation subscription data, if present.
        if accountData.hasDonationSubscriberData {
            let donationSubscriberData = accountData.donationSubscriberData
            donationSubscriptionManager.setSubscriberID(subscriberID: donationSubscriberData.subscriberID, tx: context.tx)
            donationSubscriptionManager.setSubscriberCurrencyCode(currencyCode: donationSubscriberData.currencyCode, tx: context.tx)
            donationSubscriptionManager.setUserManuallyCancelledSubscription(value: donationSubscriberData.manuallyCancelled, tx: context.tx)
        }

        if
            accountData.hasBackupsSubscriberData,
            let subscriberID = accountData.backupsSubscriberData.subscriberID.nilIfEmpty,
            let protoIapSubscriberID = accountData.backupsSubscriberData.iapSubscriptionID
        {
            typealias IAPSubscriptionID = BackupSubscriptionManager.IAPSubscriberData.IAPSubscriptionId
            let iapSubscriptionID: IAPSubscriptionID = switch protoIapSubscriberID {
            case .purchaseToken(let value):
                    .purchaseToken(value)
            case .originalTransactionID(let value):
                    .originalTransactionId(value)
            }

            backupSubscriptionManager.restoreIAPSubscriberData(
                BackupSubscriptionManager.IAPSubscriberData(
                    subscriberId: subscriberID,
                    iapSubscriptionId: iapSubscriptionID
                ),
                tx: context.tx
            )
        }

        let backupLevel: BackupLevel?
        if accountData.accountSettings.hasBackupTier {
            guard
                let parsedLevel =
                    UInt8(exactly: accountData.accountSettings.backupTier)
                    .map(BackupLevel.init(rawValue:))
            else {
                return .failure([.restoreFrameError(
                    .invalidProtoData(.invalidBackupTier),
                    .localUser
                )])
            }
            backupLevel = parsedLevel
        } else {
            // Backups disabled
            backupLevel = nil
        }

        let backupPlan: BackupPlan
        let uploadEra: String
        switch backupLevel {
        case .paid:
            uploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: context.tx)

            let optimizeLocalStorage = accountData.accountSettings.optimizeOnDeviceStorage
            if FeatureFlags.Backups.avoidStoreKitForTesters {
                // If we're importing into a build that can't make purchases,
                // opt ourselves into "paid as tester" mode. We'll manage IAP
                // data, if there is any, separately.
                backupPlan = .paidAsTester(optimizeLocalStorage: optimizeLocalStorage)
            } else {
                backupPlan = .paid(optimizeLocalStorage: optimizeLocalStorage)
            }
        case .free:
            // The exporting client was not subscribed at export time.
            // It may have subscribed after, or not. We don't know, and we don't
            // know if it was previously subscribed and if so what its subscriberId was.
            // So we use the local era (which is probably the initial era), and assume
            // we're in the same one now as we were at export time.
            // If we subscribe (or learn about a subscription) the era will rotate,
            // invalidating our belief in any attachment uploads.
            // Querying the list endpoint will bring us up to date on the upload status
            // within this "era" otherwise.
            uploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: context.tx)
            backupPlan = .free
        case .none:
            // See above comment; the same applies
            uploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: context.tx)
            backupPlan = .disabled
        }
        do {
            try backupPlanManager.setBackupPlan(backupPlan, tx: context.tx)
        } catch {
            return .failure([.restoreFrameError(
                .failedToSetBackupPlan(error),
                .localUser,
            )])
        }

        // These MUST get set before we restore custom chat colors/wallpapers.
        context.uploadEra = uploadEra
        context.backupPlan = backupPlan

        // Restore local settings
        if accountData.hasAccountSettings {
            let settings = accountData.accountSettings
            receiptManager.setAreReadReceiptsEnabled(value: settings.readReceipts, tx: context.tx)
            preferences.setShouldShowUnidentifiedDeliveryIndicators(value: settings.sealedSenderIndicators, tx: context.tx)
            typingIndicators.setTypingIndicatorsEnabled(value: settings.typingIndicators, tx: context.tx)
            linkPreviewSettingStore.setAreLinkPreviewsEnabled(settings.linkPreviews, tx: context.tx)
            phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                settings.notDiscoverableByPhoneNumber ? .nobody : .everybody,
                updateAccountAttributes: false, // This should be updated later, similar to storage service
                updateStorageService: false,
                authedAccount: .implicit(),
                tx: context.tx
            )
            sskPreferences.setPreferContactAvatars(value: settings.preferContactAvatars, tx: context.tx)
            disappearingMessageConfigurationStore.setUniversalTimer(
                token: DisappearingMessageToken(
                    isEnabled: settings.universalExpireTimerSeconds > 0,
                    durationSeconds: settings.universalExpireTimerSeconds
                ),
                tx: context.tx
            )
            if settings.preferredReactionEmoji.count > 0 {
                reactionManager.setCustomEmojiSet(emojis: settings.preferredReactionEmoji, tx: context.tx)
            }
            donationSubscriptionManager.setDisplayBadgesOnProfile(value: settings.displayBadgesOnProfile, tx: context.tx)
            sskPreferences.setShouldKeepMutedChatsArchived(value: settings.keepMutedChatsArchived, tx: context.tx)
            storyManager.setHasSetMyStoriesPrivacy(value: settings.hasSetMyStoriesPrivacy_p, tx: context.tx)
            systemStoryManager.setHasViewedOnboardingStory(value: settings.hasViewedOnboardingStory_p, tx: context.tx)
            storyManager.setAreStoriesEnabled(value: settings.storiesDisabled.negated, tx: context.tx)
            if settings.hasStoryViewReceiptsEnabled {
                storyManager.setAreViewReceiptsEnabled(value: settings.storyViewReceiptsEnabled, tx: context.tx)
            }
            systemStoryManager.setHasSeenGroupStoryEducationSheet(value: settings.hasSeenGroupStoryEducationSheet_p, tx: context.tx)
            usernameEducationManager.setShouldShowUsernameEducation(settings.hasCompletedUsernameOnboarding_p.negated, tx: context.tx)
            udManager.setPhoneNumberSharingMode(
                mode: { () -> PhoneNumberSharingMode in
                    switch settings.phoneNumberSharingMode {
                    case .unknown, .UNRECOGNIZED:
                        return .defaultValue
                    case .everybody:
                        return .everybody
                    case .nobody:
                        return .nobody
                    }
                }(),
                tx: context.tx
            )

            let customChatColorsResult = chatStyleArchiver.restoreCustomChatColors(
                settings.customChatColors,
                context: chatColorsContext
            )
            switch customChatColorsResult {
            case .success:
                break
            case .unrecognizedEnum:
                return customChatColorsResult
            case .partialRestore(let errors):
                partialErrors.append(contentsOf: errors)
            case .failure(let errors):
                partialErrors.append(contentsOf: errors)
                return .failure(partialErrors)
            }

            // This has to happen _after_ we restore custom chat colors, because
            // the default chat style might use a custom chat color.
            let defaultChatStyleToRestore: BackupProto_ChatStyle?
            if settings.hasDefaultChatStyle {
                defaultChatStyleToRestore = settings.defaultChatStyle
            } else {
                defaultChatStyleToRestore = nil
            }
            let defaultChatStyleResult = chatStyleArchiver.restoreDefaultChatStyle(
                defaultChatStyleToRestore,
                context: chatColorsContext
            )
            switch defaultChatStyleResult {
            case .success:
                break
            case .unrecognizedEnum:
                return defaultChatStyleResult
            case .partialRestore(let errors):
                partialErrors.append(contentsOf: errors)
            case .failure(let errors):
                return .failure(errors)
            }
        }

        // Restore username details (username, link, QR color)
        if accountData.hasUsername, accountData.hasUsernameLink {
            let username = accountData.username
            let usernameLink = accountData.usernameLink

            if
                let handle = UUID(data: usernameLink.serverID),
                let linkData = Usernames.UsernameLink(handle: handle, entropy: usernameLink.entropy)
            {
                localUsernameManager.setLocalUsername(username: username, usernameLink: linkData, tx: context.tx)
            } else {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidLocalUsernameLink), .localUser)])
            }

            localUsernameManager.setUsernameLinkQRCodeColor(color: usernameLink.color.qrCodeColor, tx: context.tx)
        }

        if !accountData.svrPin.isEmpty {
            ows2FAManager.restorePinFromBackup(accountData.svrPin, tx: context.tx)
        }

        if partialErrors.isEmpty {
            return .success
        } else {
            return .partialRestore(partialErrors)
        }
    }
}

// MARK: -

private extension QRCodeColor {
    var backupProtoColor: BackupProto_AccountData.UsernameLink.Color {
        switch self {
        case .blue: return .blue
        case .white: return .white
        case .grey: return .grey
        case .olive: return .olive
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        }
    }
}

private extension BackupProto_AccountData.UsernameLink.Color {
    var qrCodeColor: QRCodeColor {
        switch self {
        case .blue: return .blue
        case .white: return .white
        case .grey: return .grey
        case .olive: return .olive
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        case .unknown, .UNRECOGNIZED: return .unknown
        }
    }
}
