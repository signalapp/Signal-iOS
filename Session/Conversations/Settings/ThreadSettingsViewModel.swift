// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SignalUtilitiesKit
import SessionUtilitiesKit

class ThreadSettingsViewModel: SessionTableViewModel<ThreadSettingsViewModel.NavButton, ThreadSettingsViewModel.Section, ThreadSettingsViewModel.Setting> {
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
    
    public enum Section: SessionTableSection {
        case conversationInfo
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
                    model: .conversationInfo,
                    elements: [
                        SessionCell.Info(
                            id: .threadInfo,
                            leftAccessory: .threadInfo(
                                threadViewModel: threadViewModel,
                                avatarTapped: { [weak self] in
                                    self?.updateProfilePicture(threadViewModel: threadViewModel)
                                },
                                titleTapped: { [weak self] in self?.setIsEditing(true) },
                                titleChanged: { [weak self] text in self?.editedDisplayName = text }
                            ),
                            title: threadViewModel.displayName,
                            shouldHaveBackground: false
                        )
                    ]
                ),
                SectionModel(
                    model: .content,
                    elements: [
                        (threadVariant == .closedGroup ? nil :
                            SessionCell.Info(
                                id: .copyThreadId,
                                leftAccessory: .icon(
                                    UIImage(named: "ic_copy")?
                                        .withRenderingMode(.alwaysTemplate)
                                ),
                                title: (threadVariant == .openGroup ?
                                    "COPY_GROUP_URL".localized() :
                                    "vc_conversation_settings_copy_session_id_button_title".localized()
                                ),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).copy_thread_id",
                                onTap: {
                                    UIPasteboard.general.string = threadId
                                    self?.showToast(
                                        text: "copied".localized(),
                                        backgroundColor: .backgroundSecondary
                                    )
                                }
                            )
                        ),
                        
                        SessionCell.Info(
                            id: .allMedia,
                            leftAccessory: .icon(
                                UIImage(named: "actionsheet_camera_roll_black")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: MediaStrings.allMedia,
                            accessibilityIdentifier: "\(ThreadSettingsViewModel.self).all_media",
                            onTap: { [weak self] in
                                self?.transitionToScreen(
                                    MediaGalleryViewModel.createAllMediaViewController(
                                        threadId: threadId,
                                        threadVariant: threadVariant,
                                        focusedAttachmentId: nil
                                    )
                                )
                            }
                        ),
                        
                        SessionCell.Info(
                            id: .searchConversation,
                            leftAccessory: .icon(
                                UIImage(named: "conversation_settings_search")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "CONVERSATION_SETTINGS_SEARCH".localized(),
                            accessibilityIdentifier: "\(ThreadSettingsViewModel.self).search",
                            onTap: { [weak self] in
                                self?.didTriggerSearch()
                            }
                        ),
                        
                        (threadVariant != .openGroup ? nil :
                            SessionCell.Info(
                                id: .addToOpenGroup,
                                leftAccessory: .icon(
                                    UIImage(named: "ic_plus_24")?
                                        .withRenderingMode(.alwaysTemplate)
                                ),
                                title: "vc_conversation_settings_invite_button_title".localized(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).add_to_open_group",
                                onTap: { [weak self] in
                                    self?.transitionToScreen(
                                        UserSelectionVC(
                                            with: "vc_conversation_settings_invite_button_title".localized(),
                                            excluding: Set()
                                        ) { [weak self] selectedUsers in
                                            self?.addUsersToOpenGoup(selectedUsers: selectedUsers)
                                        }
                                    )
                                }
                            )
                        ),
                        
                        (threadVariant == .openGroup || threadViewModel.threadIsBlocked == true ? nil :
                            SessionCell.Info(
                                id: .disappearingMessages,
                                leftAccessory: .icon(
                                    UIImage(
                                        named: (disappearingMessagesConfig.isEnabled ?
                                            "ic_timer" :
                                            "ic_timer_disabled"
                                        )
                                    )?.withRenderingMode(.alwaysTemplate)
                                ),
                                title: "DISAPPEARING_MESSAGES".localized(),
                                subtitle: (disappearingMessagesConfig.isEnabled ?
                                    String(
                                        format: "DISAPPEARING_MESSAGES_SUBTITLE_DISAPPEAR_AFTER".localized(),
                                        arguments: [disappearingMessagesConfig.durationString]
                                    ) :
                                    "DISAPPEARING_MESSAGES_SUBTITLE_OFF".localized()
                                ),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).disappearing_messages",
                                onTap: { [weak self] in
                                    self?.transitionToScreen(
                                        SessionTableViewController(
                                            viewModel: ThreadDisappearingMessagesViewModel(
                                                threadId: threadId,
                                                config: disappearingMessagesConfig
                                            )
                                        )
                                    )
                                }
                            )
                        ),
                        
                        (!currentUserIsClosedGroupMember ? nil :
                            SessionCell.Info(
                                id: .editGroup,
                                leftAccessory: .icon(
                                    UIImage(named: "table_ic_group_edit")?
                                        .withRenderingMode(.alwaysTemplate)
                                ),
                                title: "EDIT_GROUP_ACTION".localized(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).edit_group",
                                onTap: { [weak self] in
                                    self?.transitionToScreen(EditClosedGroupVC(threadId: threadId))
                                }
                            )
                        ),

                        (!currentUserIsClosedGroupMember ? nil :
                            SessionCell.Info(
                                id: .leaveGroup,
                                leftAccessory: .icon(
                                    UIImage(named: "table_ic_group_leave")?
                                        .withRenderingMode(.alwaysTemplate)
                                ),
                                title: "LEAVE_GROUP_ACTION".localized(),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).leave_group",
                                confirmationInfo: ConfirmationModal.Info(
                                    title: "CONFIRM_LEAVE_GROUP_TITLE".localized(),
                                    explanation: (currentUserIsClosedGroupMember ?
                                        "Because you are the creator of this group it will be deleted for everyone. This cannot be undone." :
                                        "CONFIRM_LEAVE_GROUP_DESCRIPTION".localized()
                                    ),
                                    confirmTitle: "LEAVE_BUTTON_TITLE".localized(),
                                    confirmStyle: .danger,
                                    cancelStyle: .alert_text
                                ),
                                onTap: { [weak self] in
                                    Storage.shared.writeAsync { db in
                                        try MessageSender.leave(db, groupPublicKey: threadId)
                                    }
                                }
                            )
                        ),
                         
                        (threadViewModel.threadIsNoteToSelf ? nil :
                            SessionCell.Info(
                                id: .notificationSound,
                                leftAccessory: .icon(
                                    UIImage(named: "table_ic_notification_sound")?
                                        .withRenderingMode(.alwaysTemplate)
                                ),
                                title: "SETTINGS_ITEM_NOTIFICATION_SOUND".localized(),
                                rightAccessory: .dropDown(
                                    .dynamicString { notificationSound.displayName }
                                ),
                                onTap: { [weak self] in
                                    self?.transitionToScreen(
                                        SessionTableViewController(
                                            viewModel: NotificationSoundViewModel(threadId: threadId)
                                        )
                                    )
                                }
                            )
                        ),
                        
                        (threadVariant == .contact ? nil :
                            SessionCell.Info(
                                id: .notificationMentionsOnly,
                                leftAccessory: .icon(
                                    UIImage(named: "NotifyMentions")?
                                        .withRenderingMode(.alwaysTemplate)
                                ),
                                title: "vc_conversation_settings_notify_for_mentions_only_title".localized(),
                                subtitle: "vc_conversation_settings_notify_for_mentions_only_explanation".localized(),
                                rightAccessory: .toggle(
                                    .boolValue(threadViewModel.threadOnlyNotifyForMentions == true)
                                ),
                                isEnabled: (
                                    threadViewModel.threadVariant != .closedGroup ||
                                    currentUserIsClosedGroupMember
                                ),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).notify_for_mentions_only",
                                onTap: {
                                    let newValue: Bool = !(threadViewModel.threadOnlyNotifyForMentions == true)
                                    
                                    Storage.shared.writeAsync { db in
                                        try SessionThread
                                            .filter(id: threadId)
                                            .updateAll(
                                                db,
                                                SessionThread.Columns.onlyNotifyForMentions
                                                    .set(to: newValue)
                                            )
                                    }
                                }
                            )
                        ),
                        
                        (threadViewModel.threadIsNoteToSelf ? nil :
                            SessionCell.Info(
                                id: .notificationMute,
                                leftAccessory: .icon(
                                    UIImage(named: "Mute")?
                                        .withRenderingMode(.alwaysTemplate)
                                ),
                                title: "CONVERSATION_SETTINGS_MUTE_LABEL".localized(),
                                rightAccessory: .toggle(
                                    .boolValue(threadViewModel.threadMutedUntilTimestamp != nil)
                                ),
                                isEnabled: (
                                    threadViewModel.threadVariant != .closedGroup ||
                                    currentUserIsClosedGroupMember
                                ),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).mute",
                                onTap: {
                                    let newValue: Bool = !(threadViewModel.threadMutedUntilTimestamp != nil)
                                    
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
                            SessionCell.Info(
                                id: .blockUser,
                                leftAccessory: .icon(
                                    UIImage(named: "table_ic_block")?
                                        .withRenderingMode(.alwaysTemplate)
                                ),
                                title: "CONVERSATION_SETTINGS_BLOCK_THIS_USER".localized(),
                                rightAccessory: .toggle(
                                    .boolValue(threadViewModel.threadIsBlocked == true)
                                ),
                                accessibilityIdentifier: "\(ThreadSettingsViewModel.self).block",
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
                                    cancelStyle: .alert_text
                                ),
                                onTap: {
                                    let isBlocked: Bool = (threadViewModel.threadIsBlocked == true)
                                    
                                    self?.updateBlockedState(
                                        from: isBlocked,
                                        isBlocked: !isBlocked,
                                        threadId: threadId,
                                        displayName: threadViewModel.displayName
                                    )
                                }
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
    
    private func updateProfilePicture(threadViewModel: SessionThreadViewModel) {
        guard
            threadViewModel.threadVariant == .contact,
            let profile: Profile = threadViewModel.profile,
            let profileData: Data = ProfileManager.profileAvatar(profile: profile)
        else { return }
        
        let format: ImageFormat = profileData.guessedImageFormat
        let navController: UINavigationController = StyledNavigationController(
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
        
        self.transitionToScreen(navController, transitionType: .present)
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
        displayName: String
    ) {
        guard oldBlockedState != isBlocked else { return }
        
        Storage.shared.writeAsync(
            updates: { db in
                try Contact
                    .fetchOrCreate(db, id: threadId)
                    .with(isBlocked: .updateTo(isBlocked))
                    .save(db)
            },
            completion: { [weak self] db, _ in
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
                            cancelStyle: .alert_text
                        )
                    )
                    
                    self?.transitionToScreen(modal, transitionType: .present)
                }
            }
        )
    }
}
