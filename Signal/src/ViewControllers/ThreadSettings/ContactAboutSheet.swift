//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit

// MARK: - ContactAboutSheet

class ContactAboutSheet: StackSheetViewController {
    struct Context {
        let contactManager: any ContactManager
        let identityManager: any OWSIdentityManager
        let recipientDatabaseTable: any RecipientDatabaseTable
        let nicknameManager: any NicknameManager

        static let `default` = Context(
            contactManager: SSKEnvironment.shared.contactManagerRef,
            identityManager: DependenciesBridge.shared.identityManager,
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable,
            nicknameManager: DependenciesBridge.shared.nicknameManager
        )
    }

    private let thread: TSContactThread
    private let isLocalUser: Bool
    private let spoilerState: SpoilerRenderState
    private let context: Context

    init(
        thread: TSContactThread,
        spoilerState: SpoilerRenderState,
        context: Context = .default
    ) {
        self.thread = thread
        self.isLocalUser = thread.isNoteToSelf
        self.spoilerState = spoilerState
        self.context = context
        super.init()
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    private weak var fromViewController: UIViewController?

    func present(
        from viewController: UIViewController,
        dismissalDelegate: (any SheetDismissalDelegate)? = nil
    ) {
        self.fromViewController = viewController
        self.dismissalDelegate = dismissalDelegate
        viewController.present(self, animated: true)
    }

    // MARK: Layout

    private var nameLabel: ProfileDetailLabel?

    private lazy var avatarView: ConversationAvatarView = {
        let avatarView = ConversationAvatarView(
            sizeClass: .customDiameter(240),
            localUserDisplayMode: .asUser,
            badged: false
        )
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .thread(thread)
        }
        avatarView.interactionDelegate = self
        return avatarView
    }()

    private lazy var avatarViewContainer: UIView = {
        let container = UIView.container()
        container.addSubview(avatarView)
        avatarView.autoCenterInSuperview()
        avatarView.autoPinWidthToSuperview(relation: .lessThanOrEqual)
        avatarView.autoPinHeightToSuperview(relation: .lessThanOrEqual)
        return container
    }()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        stackView.spacing = 10
        stackView.alignment = .fill
        updateContents()
    }

    override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()
        loadContents()
    }

    override var stackViewInsets: UIEdgeInsets {
        let hMargin: CGFloat = {
            if UIDevice.current.isNarrowerThanIPhone6 {
                return 20
            } else {
                return 32
            }
        }()

        return .init(
            top: 24,
            leading: hMargin,
            bottom: 20,
            trailing: hMargin
        )
    }

    override var minimumBottomInsetIncludingSafeArea: CGFloat { 32 }
    override var sheetBackgroundColor: UIColor {
        UIColor.Signal.secondaryBackground
    }
    override var handleBackgroundColor: UIColor {
        UIColor.Signal.transparentSeparator
    }

    // MARK: - Content

    /// Updates the contents with a database read and reloads the view.
    private func updateContents() {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            updateContactNames(tx: tx)
            updateIsVerified(tx: tx.asV2Read)
            updateProfileBio(tx: tx)
            updateConnectionState(tx: tx)
            updateIsInSystemContacts(tx: tx)
            updateMutualGroupThreadCount(tx: tx)
            updateNote(tx: tx.asV2Read)
        }

        loadContents()
    }

    /// Reloads the view content with the existing data.
    @MainActor
    private func loadContents() {
        stackView.removeAllSubviews()

        stackView.addArrangedSubview(avatarViewContainer)
        stackView.setCustomSpacing(16, after: avatarViewContainer)

        let titleLabel = UILabel()
        titleLabel.font = .dynamicTypeTitle2.semibold()
        if isLocalUser {
            titleLabel.text = CommonStrings.you
        } else {
            titleLabel.text = OWSLocalizedString(
                "CONTACT_ABOUT_SHEET_TITLE",
                comment: "The title for a contact 'about' sheet."
            )
        }
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        let nameLabel = ProfileDetailLabel.profile(
            displayName: self.displayName,
            secondaryName: self.secondaryName
        ) { [weak self] in
            guard
                let self,
                let secondaryName = self.secondaryName,
                let nameLabel = self.nameLabel
            else { return }
            Tooltip(
                message: String(
                    format: OWSLocalizedString(
                        "CONTACT_ABOUT_SHEET_SECONDARY_NAME_TOOLTIP_MESSAGE",
                        comment: "Message for a tooltip that appears above a parenthesized name for another user, indicating that that name is the name the other user set for themself. Embeds {{name}}"
                    ),
                    secondaryName
                ),
                shouldShowCloseButton: false
            ).present(from: self, sourceView: nameLabel, arrowDirections: .down)
        }
        self.nameLabel = nameLabel
        stackView.addArrangedSubview(nameLabel)

        if isVerified {
            stackView.addArrangedSubview(ProfileDetailLabel.verified())
        }

        if let profileBio {
            stackView.addArrangedSubview(ProfileDetailLabel.profileAbout(bio: profileBio))
        }

        switch connectionState {
        case .connection:
            stackView.addArrangedSubview(ProfileDetailLabel.signalConnectionLink(
                shouldDismissOnNavigation: true,
                presentEducationFrom: fromViewController,
                dismissalDelegate: dismissalDelegate
            ))
        case .blocked:
            stackView.addArrangedSubview(ProfileDetailLabel.blocked(name: self.shortDisplayName))
        case .pending:
            stackView.addArrangedSubview(ProfileDetailLabel.pendingRequest(name: self.shortDisplayName))
        case .noConnection:
            stackView.addArrangedSubview(ProfileDetailLabel.noDirectChat(name: self.shortDisplayName))
        case nil:
            break
        }

        if isInSystemContacts {
            stackView.addArrangedSubview(ProfileDetailLabel.inSystemContacts(name: self.shortDisplayName))
        }

        let recipientAddress = thread.contactAddress
        if let phoneNumber = recipientAddress.phoneNumber {
            stackView.addArrangedSubview(ProfileDetailLabel.phoneNumber(phoneNumber, presentSuccessToastFrom: self))
        }

        if let mutualGroupThreads {
            stackView.addArrangedSubview(ProfileDetailLabel.mutualGroups(for: thread, mutualGroups: mutualGroupThreads))
        }

        if let note {
            let noteLabel = ProfileDetailLabel(
                title: note,
                icon: .contactInfoNote,
                showDetailDisclosure: true,
                shouldLineWrap: false,
                tapAction: { [weak self] in
                    self?.didTapNote()
                }
            )
            stackView.addArrangedSubview(noteLabel)
        }
    }

    // MARK: Name

    private var displayName: String = ""
    private var shortDisplayName: String = ""
    /// A secondary name to show after the primary name. Used to show a
    /// contact's profile name when it is overridden by a nickname.
    private var secondaryName: String?
    private func updateContactNames(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            let snapshot = SSKEnvironment.shared.profileManagerImplRef.localProfileSnapshot(shouldIncludeAvatar: false)
            self.displayName = snapshot.fullName ?? ""
            // contactShortName not needed for local user
            return
        }

        let displayName = self.context.contactManager.displayName(for: thread.contactAddress, tx: tx)
        self.displayName = displayName.resolvedValue()
        self.shortDisplayName = displayName.resolvedValue(useShortNameIfAvailable: true)

        if case .phoneNumber(let phoneNumber) = displayName {
            self.displayName = PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(phoneNumber.stringValue)
        }

        switch displayName {
        case .nickname:
            guard
                let profile = SSKEnvironment.shared.profileManagerRef.fetchUserProfiles(
                    for: [thread.contactAddress],
                    tx: tx
                ).first,
                let profileName = profile?.nameComponents
                    .map(DisplayName.profileName(_:))?
                    .resolvedValue(),
                profileName != displayName.resolvedValue()
            else {
                fallthrough
            }
            self.secondaryName = profileName
        case .systemContactName, .profileName, .phoneNumber, .username, .deletedAccount, .unknown:
            self.secondaryName = nil
        }
    }

    private func didTapNote() {
        self.dismiss(animated: true) { [weak fromViewController = self.fromViewController, thread = self.thread] in
            guard let fromViewController else { return }
            let noteSheet = ContactNoteSheet(
                thread: thread,
                context: .init(
                    db: DependenciesBridge.shared.db,
                    recipientDatabaseTable: self.context.recipientDatabaseTable,
                    nicknameManager: self.context.nicknameManager
                )
            )
            noteSheet.present(from: fromViewController)
        }
    }

    // MARK: Verified

    private var isVerified = false
    private func updateIsVerified(tx: DBReadTransaction) {
        isVerified = context.identityManager.verificationState(for: thread.contactAddress, tx: tx) == .verified
    }

    // MARK: Bio

    private var profileBio: String?
    private func updateProfileBio(tx: SDSAnyReadTransaction) {
        profileBio = SSKEnvironment.shared.profileManagerImplRef.profileBioForDisplay(for: thread.contactAddress, transaction: tx)
    }

    // MARK: Connection

    private enum ConnectionState {
        case connection
        case blocked
        case pending
        case noConnection
    }

    private var connectionState: ConnectionState?
    private func updateConnectionState(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            connectionState = nil
        } else if SSKEnvironment.shared.profileManagerRef.isThread(inProfileWhitelist: thread, transaction: tx) {
            connectionState = .connection
        } else if SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(thread.contactAddress, transaction: tx) {
            connectionState = .blocked
        } else if thread.hasPendingMessageRequest(transaction: tx) {
            connectionState = .pending
        } else {
            connectionState = .noConnection
        }
    }

    // MARK: System contacts

    private var isInSystemContacts = false
    private func updateIsInSystemContacts(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            isInSystemContacts = false
            return
        }
        isInSystemContacts = self.context.contactManager.fetchSignalAccount(for: thread.contactAddress, transaction: tx) != nil
    }

    // MARK: Threads

    private var mutualGroupThreads: [TSGroupThread]?
    private func updateMutualGroupThreadCount(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            mutualGroupThreads = nil
            return
        }

        mutualGroupThreads = TSGroupThread.groupThreads(
            with: self.thread.contactAddress,
            transaction: tx
        )
        .filter(\.isLocalUserFullMember)
        .filter(\.shouldThreadBeVisible)
        // We don't want to show "no groups in common",
        // so return nil instead of an empty array.
        .nilIfEmpty
    }

    // MARK: Note

    private var note: String?
    private func updateNote(tx: DBReadTransaction) {
        guard let recipient = context.recipientDatabaseTable.fetchRecipient(
            address: thread.contactAddress,
            tx: tx
        ) else {
            self.note = nil
            return
        }
        let nicknameRecord = context.nicknameManager.fetchNickname(for: recipient, tx: tx)
        self.note = nicknameRecord?.note
    }
}

// MARK: - DatabaseChangeDelegate

extension ContactAboutSheet: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: SignalServiceKit.DatabaseChanges) {
        guard databaseChanges.didUpdate(thread: thread) else { return }
        updateContents()
    }

    func databaseChangesDidUpdateExternally() {
        updateContents()
    }

    func databaseChangesDidReset() {
        updateContents()
    }
}

// MARK: - ConversationAvatarViewDelegate

extension ContactAboutSheet: ConversationAvatarViewDelegate {
    func didTapBadge() {
        // Badges are not shown on contact about sheet
    }

    func presentStoryViewController() {
        let vc = StoryPageViewController(
            context: self.thread.storyContext,
            spoilerState: self.spoilerState
        )
        present(vc, animated: true)
    }

    func presentAvatarViewController() {
        guard
            avatarView.primaryImage != nil,
            let vc = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                AvatarViewController(
                    thread: self.thread,
                    renderLocalUserAsNoteToSelf: false,
                    readTx: tx
                )
            })
        else {
            return
        }

        present(vc, animated: true)
    }
}

// MARK: - AvatarViewPresentationContextProvider

extension ContactAboutSheet: AvatarViewPresentationContextProvider {
    var conversationAvatarView: ConversationAvatarView? { avatarView }
}
