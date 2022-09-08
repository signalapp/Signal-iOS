// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SignalUtilitiesKit
import SessionUtilitiesKit

class ThreadSettingsViewModel: SettingsTableViewModel<ThreadSettingsViewModel.NavButton, ThreadSettingsViewModel.Section, ThreadSettingsViewModel.Setting> {
    // MARK: - Config
    
    enum NavState {
        case standard
        case editing
    }
    
    enum NavButton: Equatable {
        case edit
        case cancel
        case done
    }
    
    public enum Section: SettingSection {
        case content
    }
    
    public enum Setting: Differentiable {
        case threadInfo
        case copyThreadId
        case allMedia
        case searchConversation
        case addToOpenGroup
        case disappearingMessages
        case disappearingMessagesDuration
        case editGroup
        case leaveGroup
        case notificationSound
        case notificationMentionsOnly
        case notificationMute
        case blockUser
    }
    
    // MARK: - Variables
    
    private let threadId: String
    private let threadVariant: SessionThread.Variant
    private let didTriggerSearch: () -> ()
    private var oldDisplayName: String?
    private var editedDisplayName: String?
    
    // MARK: - Initialization
    
    init(threadId: String, threadVariant: SessionThread.Variant, didTriggerSearch: @escaping () -> ()) {
        self.threadId = threadId
        self.threadVariant = threadVariant
        self.didTriggerSearch = didTriggerSearch
        self.oldDisplayName = (threadVariant != .contact ?
            nil :
            Storage.shared.read { db in
                try Profile
                    .filter(id: threadId)
                    .select(.nickname)
                    .asRequest(of: String.self)
                    .fetchOne(db)
            }
       )
    }
    
    // MARK: - Navigation
    
    lazy var navState: AnyPublisher<NavState, Never> = {
        Publishers
            .MergeMany(
                isEditing
                    .filter { $0 }
                    .map { _ in .editing }
                    .eraseToAnyPublisher(),
                navItemTapped
                    .filter { $0 == .edit }
                    .map { _ in .editing }
                    .handleEvents(receiveOutput: { [weak self] _ in
                        self?.setIsEditing(true)
                    })
                    .eraseToAnyPublisher(),
                navItemTapped
                    .filter { $0 == .cancel }
                    .map { _ in .standard }
                    .handleEvents(receiveOutput: { [weak self] _ in
                        self?.setIsEditing(false)
                        self?.editedDisplayName = self?.oldDisplayName
                    })
                    .eraseToAnyPublisher(),
                navItemTapped
                    .filter { $0 == .done }
                    .filter { [weak self] _ in self?.threadVariant == .contact }
                    .handleEvents(receiveOutput: { [weak self] _ in
                        self?.setIsEditing(false)
                        
                        guard
                            let threadId: String = self?.threadId,
                            let editedDisplayName: String = self?.editedDisplayName
                        else { return }
                        
                        let updatedNickname: String = editedDisplayName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        self?.oldDisplayName = (updatedNickname.isEmpty ? nil : editedDisplayName)

                        Storage.shared.writeAsync { db in
                            try Profile
                                .filter(id: threadId)
                                .updateAll(
                                    db,
                                    Profile.Columns.nickname
                                        .set(to: (updatedNickname.isEmpty ? nil : editedDisplayName))
                                )
                        }
                    })
                    .map { _ in .standard }
                    .eraseToAnyPublisher()
            )
            .removeDuplicates()
            .prepend(.standard)     // Initial value
            .eraseToAnyPublisher()
    }()

    override var leftNavItems: AnyPublisher<[NavItem]?, Never> {
       navState
           .map { [weak self] navState -> [NavItem] in
               // Only show the 'Edit' button if it's a contact thread
               guard self?.threadVariant == .contact else { return [] }
               guard navState == .editing else { return [] }

               return [
                   NavItem(
                       id: .cancel,
                       systemItem: .cancel,
                       accessibilityIdentifier: "Cancel button"
                   )
               ]
           }
           .eraseToAnyPublisher()
    }

    override var rightNavItems: AnyPublisher<[NavItem]?, Never> {
       navState
           .map { [weak self] navState -> [NavItem] in
               // Only show the 'Edit' button if it's a contact thread
               guard self?.threadVariant == .contact else { return [] }

               switch navState {
                   case .editing:
                       return [
                           NavItem(
                               id: .done,
                               systemItem: .done,
                               accessibilityIdentifier: "Done button"
                           )
                       ]

                   case .standard:
                       return [
                           NavItem(
                               id: .edit,
                               systemItem: .edit,
                               accessibilityIdentifier: "Edit button"
                           )
                       ]
               }
           }
           .eraseToAnyPublisher()
    }
    
    // MARK: - Content
    
    override var title: String {
        switch threadVariant {
            case .contact: return "vc_settings_title".localized()
            case .closedGroup, .openGroup: return "vc_group_settings_title".localized()
        }
    }
    
    private var _settingsData: [SectionModel] = []
    public override var settingsData: [SectionModel] { _settingsData }
    
    public override var observableSettingsData: ObservableData { _observableSettingsData }
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** This observation will be triggered twice immediately (and be de-duped by the `removeDuplicates`)
    /// this is due to the behaviour of `ValueConcurrentObserver.asyncStartObservation` which triggers it's own
    /// fetch (after the ones in `ValueConcurrentObserver.asyncStart`/`ValueConcurrentObserver.syncStart`)
    /// just in case the database has changed between the two reads - unfortunately it doesn't look like there is a way to prevent this
    private lazy var _observableSettingsData: ObservableData = ValueObservation
        .trackingConstantRegion { [weak self, threadId = self.threadId, threadVariant = self.threadVariant] db -> [SectionModel] in
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            let maybeThreadViewModel: SessionThreadViewModel? = try SessionThreadViewModel
                .conversationSettingsQuery(threadId: threadId, userPublicKey: userPublicKey)
                .fetchOne(db)
            
            guard let threadViewModel: SessionThreadViewModel = maybeThreadViewModel else { return [] }
            
            // Additional Queries
            let fallbackSound: Preferences.Sound = db[.defaultNotificationSound]
                .defaulting(to: Preferences.Sound.defaultNotificationSound)
            let notificationSound: Preferences.Sound = try SessionThread
                .filter(id: threadId)
                .select(.notificationSound)
                .asRequest(of: Preferences.Sound.self)
                .fetchOne(db)
                .defaulting(to: fallbackSound)
            let disappearingMessagesConfig: DisappearingMessagesConfiguration = try DisappearingMessagesConfiguration
                .fetchOne(db, id: threadId)
                .defaulting(to: DisappearingMessagesConfiguration.defaultWith(threadId))
            let currentUserIsClosedGroupMember: Bool = (
                threadVariant == .closedGroup &&
                threadViewModel.currentUserIsClosedGroupMember == true
            )
            
            return [
                SectionModel(
                    model: .content,
                    elements: [
                        SettingInfo(
                            id: .threadInfo,
                            title: threadViewModel.displayName,
                            action: .threadInfo(
                                threadViewModel: threadViewModel,
                                createAvatarTapDestination: { [weak self] in
                                    guard
                                        threadVariant == .contact,
                                        let profileData: Data = ProfileManager.profileAvatar(id: threadId)
                                    else { return nil }
                                    
                                    let format: ImageFormat = profileData.guessedImageFormat
                                    let navController: UINavigationController = UINavigationController(
                                        rootViewController: ProfilePictureVC(
                                            image: (format == .gif || format == .webp ?
                                                nil :
                                                UIImage(data: profileData)
                                            ),
                                            animatedImage: (format != .gif && format != .webp ?
                                                nil :
                                                YYImage(data: profileData)
                                            ),
                                            title: threadViewModel.displayName
                                        )
                                    )
                                    navController.modalPresentationStyle = .fullScreen
                                    
                                    return navController
                                },
                                titleTapped: { [weak self] in self?.setIsEditing(true) },
                                titleChanged: { [weak self] text in self?.editedDisplayName = text }
                            )
                        ),
                        
                        (threadVariant == .closedGroup ? nil :
                            SettingInfo(
                                id: .copyThreadId,
                                icon: UIImage(named: "ic_copy")?
                                    .withRenderingMode(.alwaysTemplate),
                                title: (threadVariant == .openGroup ?
                                    "COPY_GROUP_URL".localized() :
                                    "vc_conversation_settings_copy_session_id_button_title".localized()
                                ),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).copy_thread_id",
                                action: .trigger(showChevron: false) {
                                    UIPasteboard.general.string = threadId
                                }
                            )
                        ),
                        
                        SettingInfo(
                            id: .allMedia,
                            icon: UIImage(named: "actionsheet_camera_roll_black")?
                                .withRenderingMode(.alwaysTemplate),
                            title: MediaStrings.allMedia,
                            accessibilityIdentifier: "\(ThreadSettingsViewModel.self).all_media",
                            action: .push(showChevron: false) {
                                return MediaGalleryViewModel.createTileViewController(
                                    threadId: threadId,
                                    threadVariant: threadVariant,
                                    focusedAttachmentId: nil
                                )
                            }
                        ),
                        
                        SettingInfo(
                            id: .searchConversation,
                            icon: UIImage(named: "conversation_settings_search")?
                                .withRenderingMode(.alwaysTemplate),
                            title: "CONVERSATION_SETTINGS_SEARCH".localized(),
                            accessibilityIdentifier: "\(ThreadSettingsViewModel.self).search",
                            action: .trigger(showChevron: false) { [weak self] in
                                self?.didTriggerSearch()
                            }
                        ),
                        
                        (threadVariant != .openGroup ? nil :
                            SettingInfo(
                                id: .addToOpenGroup,
                                icon: UIImage(named: "ic_plus_24")?
                                    .withRenderingMode(.alwaysTemplate),
                                title: "vc_conversation_settings_invite_button_title".localized(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).add_to_open_group",
                                action: .push(showChevron: false) {
                                    return UserSelectionVC(
                                        with: "vc_conversation_settings_invite_button_title".localized(),
                                        excluding: Set()
                                    ) { [weak self] selectedUsers in
                                        self?.addUsersToOpenGoup(selectedUsers: selectedUsers)
                                    }
                                }
                            )
                        ),
                        
                        (threadVariant == .openGroup || threadViewModel.threadIsBlocked == true ? nil :
                            SettingInfo(
                                id: .disappearingMessages,
                                icon: UIImage(
                                    named: (disappearingMessagesConfig.isEnabled ?
                                        "ic_timer" :
                                        "ic_timer_disabled"
                                    )
                                )?.withRenderingMode(.alwaysTemplate),
                                title: "DISAPPEARING_MESSAGES".localized(),
                                subtitle: {
                                    guard threadId != userPublicKey else {
                                        return "When enabled, messages will disappear after they have been seen."
                                    }

                                    let customDisplayName: String = {
                                        switch threadVariant {
                                            case .closedGroup, .openGroup: return "the group"
                                            case .contact: return threadViewModel.displayName
                                        }
                                    }()

                                    return String(
                                        format: "When enabled, messages between you and %@ will disappear after they have been seen.",
                                        arguments: [customDisplayName]
                                    )
                                }(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).disappearing_messages",
                                action: .generalEnum(
                                    title: (disappearingMessagesConfig.isEnabled ?
                                        disappearingMessagesConfig.durationString :
                                        "DISAPPEARING_MESSAGES_OFF".localized()
                                    ),
                                    createUpdateScreen: {
                                        SettingsTableViewController(
                                            viewModel: ThreadDisappearingMessagesViewModel(
                                                threadId: threadId,
                                                config: disappearingMessagesConfig
                                            )
                                        )
                                    }
                                )
                            )
                        ),
                        
                        (!currentUserIsClosedGroupMember ? nil :
                            SettingInfo(
                                id: .editGroup,
                                icon: UIImage(named: "table_ic_group_edit")?
                                    .withRenderingMode(.alwaysTemplate),
                                title: "EDIT_GROUP_ACTION".localized(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).edit_group",
                                action: .push(showChevron: false) {
                                    EditClosedGroupVC(threadId: threadId)
                                }
                            )
                        ),

                        (!currentUserIsClosedGroupMember ? nil :
                            SettingInfo(
                                id: .leaveGroup,
                                icon: UIImage(named: "table_ic_group_leave")?
                                    .withRenderingMode(.alwaysTemplate),
                                title: "LEAVE_GROUP_ACTION".localized(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).leave_group",
                                action: .present {
                                    ConfirmationModal(
                                        info: ConfirmationModal.Info(
                                            title: "CONFIRM_LEAVE_GROUP_TITLE".localized(),
                                            explanation: (currentUserIsClosedGroupMember ?
                                                "Because you are the creator of this group it will be deleted for everyone. This cannot be undone." :
                                                "CONFIRM_LEAVE_GROUP_DESCRIPTION".localized()
                                            ),
                                            confirmTitle: "LEAVE_BUTTON_TITLE".localized(),
                                            confirmStyle: .danger,
                                            cancelStyle: .textPrimary
                                        ) { _ in
                                            Storage.shared.writeAsync { db in
                                                try MessageSender.leave(db, groupPublicKey: threadId)
                                            }
                                        }
                                    )
                                }
                            )
                        ),
                         
                        (threadViewModel.threadIsNoteToSelf ? nil :
                            SettingInfo(
                                id: .notificationSound,
                                icon: UIImage(named: "table_ic_notification_sound")?
                                    .withRenderingMode(.alwaysTemplate),
                                title: "SETTINGS_ITEM_NOTIFICATION_SOUND".localized(),
                                action: .generalEnum(
                                    title: notificationSound.displayName,
                                    createUpdateScreen: {
                                        SettingsTableViewController(
                                            viewModel: NotificationSoundViewModel(threadId: threadId)
                                        )
                                    }
                                )
                            )
                        ),
                        
                        (threadVariant == .contact ? nil :
                            SettingInfo(
                                id: .notificationMentionsOnly,
                                icon: UIImage(named: "NotifyMentions")?
                                    .withRenderingMode(.alwaysTemplate),
                                title: "vc_conversation_settings_notify_for_mentions_only_title".localized(),
                                subtitle: "vc_conversation_settings_notify_for_mentions_only_explanation".localized(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).notify_for_mentions_only",
                                action: .customToggle(
                                    value: (threadViewModel.threadOnlyNotifyForMentions == true),
                                    isEnabled: (
                                        threadViewModel.threadVariant != .closedGroup ||
                                        currentUserIsClosedGroupMember
                                    )
                                ) { newValue in
                                    Storage.shared.writeAsync { db in
                                        try SessionThread
                                            .filter(id: threadId)
                                            .updateAll(
                                                db,
                                                SessionThread.Columns.onlyNotifyForMentions.set(to: newValue)
                                            )
                                    }
                                }
                            )
                        ),
                        
                        (threadViewModel.threadIsNoteToSelf ? nil :
                            SettingInfo(
                                id: .notificationMute,
                                icon: UIImage(named: "Mute")?
                                    .withRenderingMode(.alwaysTemplate),
                                title: "CONVERSATION_SETTINGS_MUTE_LABEL".localized(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).mute",
                                action: .customToggle(
                                    value: (threadViewModel.threadMutedUntilTimestamp != nil),
                                    isEnabled: (
                                        threadViewModel.threadVariant != .closedGroup ||
                                        currentUserIsClosedGroupMember
                                    )
                                ) { newValue in
                                    Storage.shared.writeAsync { db in
                                        try SessionThread
                                            .filter(id: threadId)
                                            .updateAll(
                                                db,
                                                SessionThread.Columns.mutedUntilTimestamp.set(
                                                    to: (newValue ?
                                                        Date.distantFuture.timeIntervalSince1970 :
                                                        nil
                                                    )
                                                )
                                            )
                                    }
                                }
                            )
                        ),
                        
                        (threadViewModel.threadIsNoteToSelf || threadVariant != .contact ? nil :
                            SettingInfo(
                                id: .blockUser,
                                icon: UIImage(named: "table_ic_block")?
                                    .withRenderingMode(.alwaysTemplate),
                                title: "CONVERSATION_SETTINGS_BLOCK_THIS_USER".localized(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).block",
                                action: .customToggle(
                                    value: (threadViewModel.threadIsBlocked == true),
                                    confirmationInfo: ConfirmationModal.Info(
                                        title: {
                                            guard threadViewModel.threadIsBlocked == true else {
                                                return String(
                                                    format: "BLOCK_LIST_BLOCK_USER_TITLE_FORMAT".localized(),
                                                    threadViewModel.displayName
                                                )
                                            }
                                            
                                            return String(
                                                format: "BLOCK_LIST_UNBLOCK_TITLE_FORMAT".localized(),
                                                threadViewModel.displayName
                                            )
                                        }(),
                                        explanation: (threadViewModel.threadIsBlocked == true ?
                                            nil :
                                            "BLOCK_USER_BEHAVIOR_EXPLANATION".localized()
                                        ),
                                        confirmTitle: (threadViewModel.threadIsBlocked == true ?
                                            "BLOCK_LIST_UNBLOCK_BUTTON".localized() :
                                            "BLOCK_LIST_BLOCK_BUTTON".localized()
                                        ),
                                        confirmStyle: .danger,
                                        cancelStyle: .textPrimary
                                    ) { viewController in
                                        let isBlocked: Bool = (threadViewModel.threadIsBlocked == true)
                                        
                                        self?.updateBlockedState(
                                            from: isBlocked,
                                            isBlocked: !isBlocked,
                                            threadId: threadId,
                                            displayName: threadViewModel.displayName,
                                            viewController: viewController
                                        )
                                    }
                                )
                            )
                        )
                    ].compactMap { $0 }
                )
            ]
        }
        .removeDuplicates()
        .publisher(in: Storage.shared)
    
    // MARK: - Functions

    public override func updateSettings(_ updatedSettings: [SectionModel]) {
        self._settingsData = updatedSettings
    }
    
    private func addUsersToOpenGoup(selectedUsers: Set<String>) {
        let threadId: String = self.threadId
        
        Storage.shared.writeAsync { db in
            guard let openGroup: OpenGroup = try OpenGroup.fetchOne(db, id: threadId) else { return }
            
            let urlString: String = "\(openGroup.server)/\(openGroup.roomToken)?public_key=\(openGroup.publicKey)"
            
            try selectedUsers.forEach { userId in
                let thread: SessionThread = try SessionThread.fetchOrCreate(db, id: userId, variant: .contact)
                
                try LinkPreview(
                    url: urlString,
                    variant: .openGroupInvitation,
                    title: openGroup.name
                )
                .save(db)
                
                let interaction: Interaction = try Interaction(
                    threadId: thread.id,
                    authorId: userId,
                    variant: .standardOutgoing,
                    timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000)),
                    expiresInSeconds: try? DisappearingMessagesConfiguration
                        .select(.durationSeconds)
                        .filter(id: userId)
                        .filter(DisappearingMessagesConfiguration.Columns.isEnabled == true)
                        .asRequest(of: TimeInterval.self)
                        .fetchOne(db),
                    linkPreviewUrl: urlString
                )
                .inserted(db)
                
                try MessageSender.send(
                    db,
                    interaction: interaction,
                    in: thread
                )
            }
        }
    }
    
    private func updateBlockedState(
        from oldBlockedState: Bool,
        isBlocked: Bool,
        threadId: String,
        displayName: String,
        viewController: UIViewController
    ) {
        guard oldBlockedState != isBlocked else { return }
        
        Storage.shared.writeAsync(
            updates: { db in
                try Contact
                    .fetchOrCreate(db, id: threadId)
                    .with(isBlocked: .updateTo(isBlocked))
                    .save(db)
            },
            completion: { db, _ in
                try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
                
                DispatchQueue.main.async {
                    let modal: ConfirmationModal = ConfirmationModal(
                        info: ConfirmationModal.Info(
                            title: (oldBlockedState == false ?
                                "BLOCK_LIST_VIEW_BLOCKED_ALERT_TITLE".localized() :
                                String(
                                    format: "BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT".localized(),
                                    displayName
                                )
                            ),
                            explanation: (oldBlockedState == false ?
                                String(
                                    format: "BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT".localized(),
                                    displayName
                                ) :
                                nil
                            ),
                            cancelTitle: "BUTTON_OK".localized(),
                            cancelStyle: .textPrimary
                        )
                    )
                    viewController.present(modal, animated: true)
                }
            }
        )
    }
}
