//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {
    /// An identifier for the ``BackupProto_AccountData`` backup frame.
    ///
    /// Uses a singleton pattern, as there is only ever one account data frame
    /// in a backup.
    public struct AccountDataId: MessageBackupLoggableId {
        static let localUser = AccountDataId()

        private init() {}

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto_AccountData" }
        public var idLogString: String { "localUser" }
    }

    public typealias ArchiveAccountDataResult = ArchiveSingleFrameResult<Void, AccountDataId>
    public typealias RestoreAccountDataResult = RestoreFrameResult<MessageBackup.AccountDataId>
}

/**
 * Archives the ``BackupProto_AccountData`` frame
 */
public protocol MessageBackupAccountDataArchiver: MessageBackupProtoArchiver {
    func archiveAccountData(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveAccountDataResult

    func restore(
        _ accountData: BackupProto_AccountData,
        context: MessageBackup.RestoringContext
    ) -> MessageBackup.RestoreAccountDataResult
}

public class MessageBackupAccountDataArchiverImpl: MessageBackupAccountDataArchiver {

    private let disappearingMessageConfigurationStore: DisappearingMessagesConfigurationStore
    private let linkPreviewSettingStore: LinkPreviewSettingStore
    private let localUsernameManager: LocalUsernameManager
    private let phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager
    private let preferences: MessageBackup.AccountData.Shims.Preferences
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let receiptManager: MessageBackup.AccountData.Shims.ReceiptManager
    private let reactionManager: MessageBackup.AccountData.Shims.ReactionManager
    private let sskPreferences: MessageBackup.AccountData.Shims.SSKPreferences
    private let subscriptionManager: MessageBackup.AccountData.Shims.SubscriptionManager
    private let storyManager: MessageBackup.AccountData.Shims.StoryManager
    private let systemStoryManager: MessageBackup.AccountData.Shims.SystemStoryManager
    private let typingIndicators: MessageBackup.AccountData.Shims.TypingIndicators
    private let udManager: MessageBackup.AccountData.Shims.UDManager
    private let usernameEducationManager: UsernameEducationManager

    public init(
        disappearingMessageConfigurationStore: DisappearingMessagesConfigurationStore,
        linkPreviewSettingStore: LinkPreviewSettingStore,
        localUsernameManager: LocalUsernameManager,
        phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager,
        preferences: MessageBackup.AccountData.Shims.Preferences,
        profileManager: MessageBackup.Shims.ProfileManager,
        receiptManager: MessageBackup.AccountData.Shims.ReceiptManager,
        reactionManager: MessageBackup.AccountData.Shims.ReactionManager,
        sskPreferences: MessageBackup.AccountData.Shims.SSKPreferences,
        subscriptionManager: MessageBackup.AccountData.Shims.SubscriptionManager,
        storyManager: MessageBackup.AccountData.Shims.StoryManager,
        systemStoryManager: MessageBackup.AccountData.Shims.SystemStoryManager,
        typingIndicators: MessageBackup.AccountData.Shims.TypingIndicators,
        udManager: MessageBackup.AccountData.Shims.UDManager,
        usernameEducationManager: UsernameEducationManager
    ) {
        self.disappearingMessageConfigurationStore = disappearingMessageConfigurationStore
        self.linkPreviewSettingStore = linkPreviewSettingStore
        self.localUsernameManager = localUsernameManager
        self.phoneNumberDiscoverabilityManager = phoneNumberDiscoverabilityManager
        self.preferences = preferences
        self.receiptManager = receiptManager
        self.reactionManager = reactionManager
        self.sskPreferences = sskPreferences
        self.subscriptionManager = subscriptionManager
        self.storyManager = storyManager
        self.systemStoryManager = systemStoryManager
        self.typingIndicators = typingIndicators
        self.udManager = udManager
        self.usernameEducationManager = usernameEducationManager
        self.profileManager = profileManager
    }

    public func archiveAccountData(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveAccountDataResult {

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

        if let donationSubscriberId = subscriptionManager.getSubscriberID(tx: context.tx) {
            var donationSubscriberData = BackupProto_AccountData.SubscriberData()
            donationSubscriberData.subscriberID = donationSubscriberId
            donationSubscriberData.currencyCode = subscriptionManager.getSubscriberCurrencyCode(tx: context.tx) ?? ""
            donationSubscriberData.manuallyCancelled = subscriptionManager.userManuallyCancelledSubscription(tx: context.tx)

            accountData.donationSubscriberData = donationSubscriberData
        }

        if let result = buildUsernameLinkProto(context: context) {
            accountData.username = result.username
            accountData.usernameLink = result.usernameLink
        }

        accountData.accountSettings = buildAccountSettingsProto(context: context)

        let error = Self.writeFrameToStream(stream, objectId: MessageBackup.AccountDataId.localUser) {
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

    private func buildUsernameLinkProto(
        context: MessageBackup.ArchivingContext
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
        context: MessageBackup.ArchivingContext
    ) -> BackupProto_AccountData.AccountSettings {

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
        let displayBadgesOnProfile = subscriptionManager.displayBadgesOnProfile(tx: context.tx)
        let keepMutedChatsArchived = sskPreferences.shouldKeepMutedChatsArchived(tx: context.tx)
        let hasSetMyStoriesPrivacy = storyManager.hasSetMyStoriesPrivacy(tx: context.tx)
        let hasViewedOnboardingStory = systemStoryManager.isOnboardingStoryViewed(tx: context.tx)
        let storiesDisabled = storyManager.areStoriesEnabled(tx: context.tx).negated
        let hasSeenGroupStoryEducationSheet = systemStoryManager.hasSeenGroupStoryEducationSheet(tx: context.tx)
        let hasCompletedUsernameOnboarding = usernameEducationManager.shouldShowUsernameEducation(tx: context.tx).negated
        let phoneNumberSharingMode: BackupProto_AccountData.PhoneNumberSharingMode = switch udManager.phoneNumberSharingMode(tx: context.tx) {
        case .everybody: .everybody
        case .nobody: .nobody
        case .none: .unknown
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
        // TODO: [Backups] Archive default chat style
        // TODO: [Backups] Archive custom chat colors

        return accountSettings
    }

    public func restore(
        _ accountData: BackupProto_AccountData,
        context: MessageBackup.RestoringContext
    ) -> MessageBackup.RestoreAccountDataResult {
        guard let profileKey = Aes256Key(data: accountData.profileKey) else {
            return .failure([.restoreFrameError(
                .invalidProtoData(.invalidLocalProfileKey),
                .localUser
            )])
        }

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
            subscriptionManager.setSubscriberID(subscriberID: donationSubscriberData.subscriberID, tx: context.tx)
            subscriptionManager.setSubscriberCurrencyCode(currencyCode: donationSubscriberData.currencyCode, tx: context.tx)
            subscriptionManager.setUserManuallyCancelledSubscription(value: donationSubscriberData.manuallyCancelled, tx: context.tx)
        }

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
            subscriptionManager.setDisplayBadgesOnProfile(value: settings.displayBadgesOnProfile, tx: context.tx)
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

            // TODO: [Backups] Restore default chat style
            // TODO: [Backups] Restore custom chat colors
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

        return .success
    }
}

private extension Usernames.QRCodeColor {
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
    var qrCodeColor: Usernames.QRCodeColor {
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
