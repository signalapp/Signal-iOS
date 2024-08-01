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
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveAccountDataResult

    func restore(
        _ accountData: BackupProto_AccountData,
        tx: DBWriteTransaction
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
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveAccountDataResult {

        guard let localProfile = profileManager.getUserProfileForLocalUser(tx: tx) else {
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

        if let donationSubscriberId = subscriptionManager.getSubscriberID(tx: tx) {
            var donationSubscriberData = BackupProto_AccountData.SubscriberData()
            donationSubscriberData.subscriberID = donationSubscriberId
            donationSubscriberData.currencyCode = subscriptionManager.getSubscriberCurrencyCode(tx: tx) ?? ""
            donationSubscriberData.manuallyCancelled = subscriptionManager.userManuallyCancelledSubscription(tx: tx)

            accountData.donationSubscriberData = donationSubscriberData
        }

        if let result = buildUsernameLinkProto(tx: tx) {
            accountData.username = result.username
            accountData.usernameLink = result.usernameLink
        }

        accountData.accountSettings = buildAccountSettingsProto(tx: tx)

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

    private func buildUsernameLinkProto(tx: DBReadTransaction) -> (username: String, usernameLink: BackupProto_AccountData.UsernameLink)? {
        switch self.localUsernameManager.usernameState(tx: tx) {
        case .unset, .linkCorrupted, .usernameAndLinkCorrupted:
            return nil
        case .available(let username, let usernameLink):
            var usernameLinkProto = BackupProto_AccountData.UsernameLink()
            usernameLinkProto.entropy = usernameLink.entropy
            usernameLinkProto.serverID = usernameLink.handle.data
            usernameLinkProto.color = localUsernameManager.usernameLinkQRCodeColor(tx: tx).backupProtoColor

            return (username, usernameLinkProto)
        }
    }

    private func buildAccountSettingsProto(tx: DBReadTransaction) -> BackupProto_AccountData.AccountSettings {

        // Fetch all the account settings
        let readReceipts = receiptManager.areReadReceiptsEnabled(tx: tx)
        let sealedSenderIndicators = preferences.shouldShowUnidentifiedDeliveryIndicators(tx: tx)
        let typingIndicatorsEnabled = typingIndicators.areTypingIndicatorsEnabled()
        let linkPreviews = linkPreviewSettingStore.areLinkPreviewsEnabled(tx: tx)
        let notDiscoverableByPhoneNumber = switch phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: tx) {
        case .everybody: false
        case .nobody, .none: true
        }
        let preferContactAvatars = sskPreferences.preferContactAvatars(tx: tx)
        let universalExpireTimerSeconds = disappearingMessageConfigurationStore.fetchOrBuildDefault(for: .universal, tx: tx).durationSeconds
        let displayBadgesOnProfile = subscriptionManager.displayBadgesOnProfile(tx: tx)
        let keepMutedChatsArchived = sskPreferences.shouldKeepMutedChatsArchived(tx: tx)
        let hasSetMyStoriesPrivacy = storyManager.hasSetMyStoriesPrivacy(tx: tx)
        let hasViewedOnboardingStory = systemStoryManager.isOnboardingStoryViewed(tx: tx)
        let storiesDisabled = storyManager.areStoriesEnabled(tx: tx).negated
        let hasSeenGroupStoryEducationSheet = systemStoryManager.hasSeenGroupStoryEducationSheet(tx: tx)
        let hasCompletedUsernameOnboarding = usernameEducationManager.shouldShowUsernameEducation(tx: tx).negated
        let phoneNumberSharingMode: BackupProto_AccountData.PhoneNumberSharingMode = switch udManager.phoneNumberSharingMode(tx: tx) {
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
        accountSettings.preferredReactionEmoji = reactionManager.customEmojiSet(tx: tx) ?? []
        accountSettings.storyViewReceiptsEnabled = storyManager.areViewReceiptsEnabled(tx: tx)
        // TODO: [Backups] Archive default chat style
        // TODO: [Backups] Archive custom chat colors

        return accountSettings
    }

    public func restore(
        _ accountData: BackupProto_AccountData,
        tx: DBWriteTransaction
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
            tx: tx
        )

        // Restore donation subscription data, if present.
        if accountData.hasDonationSubscriberData {
            let donationSubscriberData = accountData.donationSubscriberData
            subscriptionManager.setSubscriberID(subscriberID: donationSubscriberData.subscriberID, tx: tx)
            subscriptionManager.setSubscriberCurrencyCode(currencyCode: donationSubscriberData.currencyCode, tx: tx)
            subscriptionManager.setUserManuallyCancelledSubscription(value: donationSubscriberData.manuallyCancelled, tx: tx)
        }

        // Restore local settings
        if accountData.hasAccountSettings {
            let settings = accountData.accountSettings
            receiptManager.setAreReadReceiptsEnabled(value: settings.readReceipts, tx: tx)
            preferences.setShouldShowUnidentifiedDeliveryIndicators(value: settings.sealedSenderIndicators, tx: tx)
            typingIndicators.setTypingIndicatorsEnabled(value: settings.typingIndicators, tx: tx)
            linkPreviewSettingStore.setAreLinkPreviewsEnabled(settings.linkPreviews, tx: tx)
            phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                settings.notDiscoverableByPhoneNumber ? .nobody : .everybody,
                updateAccountAttributes: false, // This should be updated later, similar to storage service
                updateStorageService: false,
                authedAccount: .implicit(),
                tx: tx
            )
            sskPreferences.setPreferContactAvatars(value: settings.preferContactAvatars, tx: tx)
            disappearingMessageConfigurationStore.set(
                token: DisappearingMessageToken(
                    isEnabled: settings.universalExpireTimerSeconds > 0,
                    durationSeconds: settings.universalExpireTimerSeconds
                ),
                for: .universal,
                tx: tx
            )
            if settings.preferredReactionEmoji.count > 0 {
                reactionManager.setCustomEmojiSet(emojis: settings.preferredReactionEmoji, tx: tx)
            }
            subscriptionManager.setDisplayBadgesOnProfile(value: settings.displayBadgesOnProfile, tx: tx)
            sskPreferences.setShouldKeepMutedChatsArchived(value: settings.keepMutedChatsArchived, tx: tx)
            storyManager.setHasSetMyStoriesPrivacy(value: settings.hasSetMyStoriesPrivacy_p, tx: tx)
            systemStoryManager.setHasViewedOnboardingStory(value: settings.hasViewedOnboardingStory_p, tx: tx)
            storyManager.setAreStoriesEnabled(value: settings.storiesDisabled.negated, tx: tx)
            if settings.hasStoryViewReceiptsEnabled {
                storyManager.setAreViewReceiptsEnabled(value: settings.storyViewReceiptsEnabled, tx: tx)
            }
            systemStoryManager.setHasSeenGroupStoryEducationSheet(value: settings.hasSeenGroupStoryEducationSheet_p, tx: tx)
            usernameEducationManager.setShouldShowUsernameEducation(settings.hasCompletedUsernameOnboarding_p.negated, tx: tx)
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
                tx: tx
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
                localUsernameManager.setLocalUsername(username: username, usernameLink: linkData, tx: tx)
            } else {
                return .failure([.restoreFrameError(.invalidProtoData(.invalidLocalUsernameLink), .localUser)])
            }

            localUsernameManager.setUsernameLinkQRCodeColor(color: usernameLink.color.qrCodeColor, tx: tx)
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
